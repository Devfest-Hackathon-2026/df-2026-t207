"""今日のコーデの登録と手持ち、自分の画像 (tasks の S2)。

画像は vision が置いた jobs の下の物をそのまま指す (写さない)。他人には返さない。
匿名 (Web デモの審査員) は読むだけで、デモの見る人 (DEMO_VIEWER_UID) の物を見る。
"""
import logging
import re
import secrets
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from google.cloud import firestore
from pydantic import BaseModel, Field

from auth import User, acting_uid, current_user, google_uid
from blobs import Blobs, get_blobs
from nearby import garment
from routes_me import JST, demo_today, get_db, today_jst

JOB_RE = r"[A-Za-z0-9_-]{8,64}"
router = APIRouter()


def png(blobs: Blobs, path: str | None) -> Response:
    data = blobs.get(path) if path else None
    if data is None:
        raise HTTPException(404, {"code": "not_found", "message": "見つかりません"})
    return Response(data, media_type="image/png", headers={"Cache-Control": "private, no-store"})


def item_ref(db, uid: str, item_id: str):
    if not re.fullmatch(r"w_[A-Za-z0-9_-]{1,32}", item_id):
        raise HTTPException(404, {"code": "not_found", "message": "見つかりません"})
    return db.document(f"users/{uid}/wardrobeItems/{item_id}")


def item_body(item_id: str, w: dict) -> dict:
    return {**garment(w), "itemId": item_id, "image": f"/v1/wardrobe/{item_id}/image",
            "memo": w.get("memo", ""), "createdAt": w["createdAt"].isoformat()}


def api_image(path: str) -> str:
    """Storage の users/{uid}/jobs/{jobId}/{name}.png を、本人が読める api の口 /v1/jobs/{jobId}/images/{name} にする。"""
    job, name = path.rsplit("/", 2)[-2:]
    return f"/v1/jobs/{job}/images/{name.removesuffix('.png')}"


def snap(item_id: str, w: dict) -> dict:
    """その日のコーデに写しておく服 (手持ちから消しても、投稿時点のまま見られるように)。"""
    return {**garment(w), "itemId": item_id, "memo": w.get("memo", ""), "image": api_image(w["image"])}


def today_body(db, uid: str, day: str, d: dict) -> dict:
    refs = [db.document(f"users/{uid}/wardrobeItems/{i}") for i in d.get("items", [])]
    found = {s.id: s.to_dict() for s in db.get_all(refs) if s.exists}
    memo = {s["itemId"]: s.get("memo", "") for s in d.get("snapshot", [])}  # コーデ専用のメモ (無ければ手持ちのメモ)
    items = [item_body(i, found[i] | ({"memo": memo[i]} if i in memo else {})) for i in d.get("items", []) if i in found]
    body = {"date": day, "image": "/v1/outfits/today/image", "items": items}
    if d.get("jobId"):
        body["jobId"] = d["jobId"]
    if d.get("itemNotes"):
        body["itemNotes"] = d["itemNotes"]
    return body


class Pick(BaseModel):
    """docs/api.yaml の 3 つの形: 検出した服 {index, memo?, sameAs?} / 手持ち {wardrobeItemId, memo?} / メモだけ {memo}"""
    model_config = {"extra": "forbid"}
    index: int | None = None
    wardrobeItemId: str | None = None
    sameAs: str | None = None  # 同じ服の判定で本人が「同じ」を選んだ手持ちの id (index と一緒に)
    memo: str | None = Field(None, max_length=100)

    def kind(self) -> str:
        if self.index is not None and self.wardrobeItemId is None:
            return "detected"
        if self.wardrobeItemId is not None and self.index is None and self.sameAs is None:
            return "closet"
        if self.index is None and self.wardrobeItemId is None and self.sameAs is None and (self.memo or "").strip():
            return "note"
        raise HTTPException(400, {"code": "validation", "message": "アイテムの形が正しくありません"})


def _vectors(blobs: Blobs, paths: list[str]) -> list[list[float] | None]:
    """新しく手持ちに入れる服のベクトル (同じ服の判定に使う)。作れなくても登録は止めない。"""
    import ai

    def one(path):
        try:
            return ai.embed(blobs.get(path))
        except Exception as e:
            logging.warning("embed skipped: %s", type(e).__name__)
            return None

    with ThreadPoolExecutor(4) as ex:
        return list(ex.map(one, paths))


class RegisterBody(BaseModel):
    jobId: str = Field(pattern=f"^{JOB_RE}$")
    items: list[Pick] = Field(max_length=20)
    editDate: str | None = None  # 登録済みの今日のコーデを直す時だけ (その日の日付)


@router.put("/v1/outfits/today")
def register(body: RegisterBody, user: User = Depends(current_user), db: firestore.Client = Depends(get_db),
             blobs: Blobs = Depends(get_blobs)):
    uid = google_uid(user)
    job = db.document(f"users/{uid}/jobs/{body.jobId}").get().to_dict()
    if job is None:
        raise HTTPException(404, {"code": "not_found", "message": "処理の記録が見つかりません"})
    if job.get("status") != "succeeded":
        if (job.get("error") or {}).get("code") == "face_detected":
            raise HTTPException(409, {"code": "face_detected", "message": "顔が見えているため公開できません。撮りなおしてください"})
        raise HTTPException(409, {"code": "not_ready", "message": "処理が終わっていません"})
    kinds = [p.kind() for p in body.items]
    now, day, base = datetime.now(JST), today_jst(), f"users/{uid}/jobs/{body.jobId}"
    daily_ref = db.document(f"users/{uid}/dailyOutfits/{day}")
    if body.editDate is not None:  # 今日のコーデを直す。日付と jobId が今のコーデと同じ時だけ。手持ちとメモだけを送る
        cur = daily_ref.get().to_dict() or {}
        if body.editDate != day or cur.get("jobId") != body.jobId:
            raise HTTPException(409, {"code": "conflict", "message": "日付が変わったか、今日のコーデが変わりました。開き直してください"})
        if "detected" in kinds:
            raise HTTPException(400, {"code": "validation", "message": "直す時は手持ちとメモだけを送れます"})
    elif job.get("registered"):  # 送り直し (通信が切れて結果が分からなかった時など)。新しく作らず前の結果を返す
        day = job["registered"]["date"]
        return today_body(db, uid, day, db.document(f"users/{uid}/dailyOutfits/{day}").get().to_dict() or {})

    results = {it["index"]: it for it in job["result"]["items"]}
    closet: dict[str, dict] = {}
    for p, k in zip(body.items, kinds):
        if k == "detected" and p.index not in results:
            raise HTTPException(400, {"code": "validation", "message": "選んだ服が処理の結果にありません"})
        wid = p.sameAs if k == "detected" else p.wardrobeItemId if k == "closet" else None
        if wid:
            w = item_ref(db, uid, wid).get().to_dict() if wid.startswith("w_") else None
            if not w or (k == "detected" and w.get("slot") != results[p.index].get("slot")):
                raise HTTPException(400, {"code": "validation", "message": "選んだ手持ちが見つかりません"})
            closet[wid] = w

    new = [p for p, k in zip(body.items, kinds) if k == "detected" and not p.sameAs]
    vectors = dict(zip((p.index for p in new), _vectors(blobs, [f"{base}/item-{p.index}.png" for p in new])))
    batch, ids, snapshot, notes = db.batch(), [], [], []
    for p, k in zip(body.items, kinds):
        if k == "note":
            notes.append(p.memo.strip())
            continue
        wid = p.sameAs if k == "detected" else p.wardrobeItemId
        if wid:  # 手持ちにもうある服。新しく作らず、今日のコーデにだけ入れる
            ids.append(wid)
            snapshot.append(snap(wid, closet[wid]) | ({"memo": p.memo} if p.memo is not None else {}))
            continue
        item_id = "w_" + secrets.token_urlsafe(9)
        it = results[p.index]
        doc = {**garment(it), "image": f"{base}/item-{p.index}.png", "memo": p.memo or "", "createdAt": now, "jobId": body.jobId}
        if vectors[p.index]:
            doc["vector"] = vectors[p.index]
        batch.set(db.document(f"users/{uid}/wardrobeItems/{item_id}"), doc)
        ids.append(item_id)
        snapshot.append(snap(item_id, doc))
    daily = {"items": ids, "image": f"{base}/outfit.png", "outfitImage": f"/v1/jobs/{body.jobId}/images/outfit",
             "snapshot": snapshot, "itemNotes": notes, "jobId": body.jobId}
    batch.set(daily_ref, daily, merge=True)  # 公開の状態と見られた数は残す
    batch.update(db.document(f"users/{uid}/jobs/{body.jobId}"), {"registered": {"date": day}})
    batch.commit()
    return today_body(db, uid, day, daily)


def _today(db, user: User) -> tuple[str, str, dict]:
    """(uid, 日付, 今日のコーデ)。Web デモの審査員は、デモの見る人の一番新しいコーデ (日付に依らない)"""
    uid = acting_uid(user)
    if user.is_anonymous:
        return uid, *demo_today(db, uid)
    day = today_jst()
    return uid, day, db.document(f"users/{uid}/dailyOutfits/{day}").get().to_dict() or {}


@router.get("/v1/outfits/today")
def get_today(user: User = Depends(current_user), db: firestore.Client = Depends(get_db)):
    uid, day, d = _today(db, user)
    if not d or not d.get("image"):
        raise HTTPException(404, {"code": "not_found", "message": "今日のコーデはまだ登録していません"})
    return today_body(db, uid, day, d)


@router.get("/v1/outfits/today/image")
def today_image(user: User = Depends(current_user), db=Depends(get_db), blobs: Blobs = Depends(get_blobs)):
    return png(blobs, _today(db, user)[2].get("image"))


@router.get("/v1/jobs/{jobId}/images/{name}")
def job_image(jobId: str, name: str, user: User = Depends(current_user), blobs: Blobs = Depends(get_blobs)):  # noqa: N803
    if not re.fullmatch(JOB_RE, jobId) or not re.fullmatch(r"outfit|item-\d{1,2}", name):
        raise HTTPException(404, {"code": "not_found", "message": "見つかりません"})
    return png(blobs, f"users/{user.uid}/jobs/{jobId}/{name}.png")


@router.get("/v1/wardrobe")
def wardrobe(slot: str | None = Query(None), user: User = Depends(current_user), db: firestore.Client = Depends(get_db)):
    q = db.collection(f"users/{acting_uid(user)}/wardrobeItems")
    if slot:
        q = q.where(filter=firestore.FieldFilter("slot", "==", slot))
    items = sorted((item_body(s.id, s.to_dict()) for s in q.stream()), key=lambda i: i["createdAt"], reverse=True)
    return {"items": items}


@router.delete("/v1/wardrobe/{itemId}", status_code=204)
def remove(itemId: str, user: User = Depends(current_user), db: firestore.Client = Depends(get_db)):  # noqa: N803
    item_ref(db, google_uid(user), itemId).delete()  # 切り抜きは jobs の下に残る (今日の着姿の一部なので)
    return Response(status_code=204)


@router.get("/v1/wardrobe/{itemId}/image")
def wardrobe_image(itemId: str, user: User = Depends(current_user), db=Depends(get_db), blobs: Blobs = Depends(get_blobs)):  # noqa: N803
    w = item_ref(db, acting_uid(user), itemId).get().to_dict() or {}
    return png(blobs, w.get("image"))
