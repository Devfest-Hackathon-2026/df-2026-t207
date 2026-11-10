"""フレンド (tasks の M8) とプロフィール画像。口は docs/api.yaml の friends と /v1/me/profile-image。

- 実際の友人どうしがフレンドコード (QR はアプリがコードを読む) で申請し、相互に承認した時だけ。すれ違いのカードからは辿れない
- 関係と申請は top-level の friendships/{friendId} {members, since} と friendRequests/{requestId} {from, to, createdAt} に置く
  (users/{uid} の下は Security Rules で本人が読めるので、相手の uid を置かない)。相手の uid は返さない
- フレンドに見せるのは、相手が今日「近くのユーザー」に公開したコーデだけ。プロフィール画像は承認の後だけ
- 解除・辞退は相手に知らせない。匿名 (Web デモ) は全部 403
"""
import hashlib
import io
import re
import secrets
from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, File, Form, HTTPException, Response, UploadFile
from google.api_core.exceptions import AlreadyExists
from google.cloud import firestore
from PIL import Image, ImageOps
from pydantic import BaseModel, Field

import notify
from auth import User, charge, current_user, google_uid
from blobs import Blobs, get_blobs
from cards import not_found
from nearby import CARD_TTL, garment
from outfits import png
from routes_me import JST, get_db, today_jst

CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # 紛らわしい 0/O/1/I は使わない
ID_RE = re.compile(r"[fr]_[\w-]{1,40}")
MAX_IMAGE = 10 * 2**20
MAX_PIXELS = 40_000_000
router = APIRouter()


def me(user: User = Depends(current_user)) -> str:
    return google_uid(user)


def _user(db, uid: str) -> dict:
    return db.document(f"users/{uid}").get().to_dict() or {}


def me_fields(db, uid: str) -> dict:
    """Me の friendCode・profileImage・profileCrop。コードが無ければ作る。"""
    prof = _user(db, uid)
    code = prof.get("friendCode")
    while not code:
        try:
            cand = "".join(secrets.choice(CODE_CHARS) for _ in range(8))
            db.document(f"friendCodes/{cand}").create({"uid": uid})
            db.document(f"users/{uid}").set({"friendCode": cand}, merge=True)
            code = cand
        except AlreadyExists:
            pass
    return {"friendCode": code, "profileImage": "/v1/me/profile-image" if prof.get("profileImage") else None,
            "profileCrop": prof.get("profileCrop")}


def _doc(db, coll: str, id_: str) -> dict | None:
    return db.document(f"{coll}/{id_}").get().to_dict() if ID_RE.fullmatch(id_) else None


def friend_owner(db, uid: str, friend_id: str) -> str:
    """フレンドの関係の id から相手の uid を引く (サーバの中だけで使う)。フレンドでなければ 404。"""
    f = _doc(db, "friendships", friend_id)
    if not f or uid not in f["members"]:
        raise not_found()
    return next(m for m in f["members"] if m != uid)


def _today(db, owner: str) -> dict | None:
    d = db.document(f"users/{owner}/dailyOutfits/{today_jst()}").get().to_dict() or {}
    return d if d.get("visibility") == "nearby" and d.get("image") else None


def _liked(db, uid: str, owner: str, day: str) -> bool:
    import likes  # likes が friends を import するので、関数の中で

    return likes.liked(db, uid, owner, day)


def friend_body(db, uid: str, friend_id: str, f: dict) -> dict:
    owner = next(m for m in f["members"] if m != uid)
    prof, base = _user(db, owner), f"/v1/friends/{friend_id}"
    body = {"friendId": friend_id, "displayName": prof.get("displayName", ""),
            "profileImage": f"{base}/profile-image" if prof.get("profileImage") else None,
            "profileCrop": prof.get("profileCrop"), "since": f["since"].astimezone(JST).isoformat(), "today": None}
    d = _today(db, owner)
    if d:
        day = today_jst()
        items = [{**garment(s), "image": f"{base}/today/items/{i}/image", "memo": s.get("memo", "")}
                 for i, s in enumerate(d.get("snapshot", []))]  # itemId (手持ちの id) は返さない
        body["today"] = {"date": day, "image": f"{base}/today/image", "items": items,
                         "itemNotes": d.get("itemNotes", []), "liked": _liked(db, uid, owner, day)}
    return body


def _friendships(db, uid: str):
    return db.collection("friendships").where(filter=firestore.FieldFilter("members", "array_contains", uid)).stream()


def _requests(db, field: str, uid: str):
    return db.collection("friendRequests").where(filter=firestore.FieldFilter(field, "==", uid)).stream()


def _request_body(db, rid: str, r: dict, other: str, status: str = "pending") -> dict:
    return {"requestId": rid, "displayName": _user(db, other).get("displayName", ""), "profileImage": None,
            "createdAt": r["createdAt"].isoformat(), "status": status}


def _befriend(db, a: str, b: str, now: datetime) -> tuple[str, dict, bool]:
    """2 人の組で決まる id の 1 件だけを作る (同時の承認や二度押しでも 1 件)。もうあれば作らず False。"""
    pair = sorted([a, b])
    fid = "f_" + hashlib.sha256(" ".join(pair).encode()).hexdigest()[:22]  # uid に空白は入らない
    ref, f = db.document(f"friendships/{fid}"), {"members": pair, "since": now}
    try:
        ref.create(f)
        return fid, f, True
    except AlreadyExists:
        return fid, ref.get().to_dict(), False


def _name(db, uid: str) -> str:
    return _user(db, uid).get("displayName", "")


@router.get("/v1/friends")
def list_friends(uid: str = Depends(me), db: firestore.Client = Depends(get_db)):
    fs = sorted(_friendships(db, uid), key=lambda s: s.to_dict()["since"])
    return {"friends": [friend_body(db, uid, s.id, s.to_dict()) for s in fs]}


@router.delete("/v1/friends/{friendId}", status_code=204)
def unfriend(friendId: str, uid: str = Depends(me), db: firestore.Client = Depends(get_db)):  # noqa: N803
    friend_owner(db, uid, friendId)
    db.document(f"friendships/{friendId}").delete()
    return Response(status_code=204)


@router.get("/v1/friends/{friendId}/today/image")
def friend_today_image(friendId: str, uid: str = Depends(me), db=Depends(get_db), blobs: Blobs = Depends(get_blobs)):  # noqa: N803
    d = _today(db, friend_owner(db, uid, friendId)) or {}
    return png(blobs, d.get("image"))


@router.get("/v1/friends/{friendId}/today/items/{index}/image")
def friend_item_image(friendId: str, index: int, uid: str = Depends(me), db=Depends(get_db),  # noqa: N803
                      blobs: Blobs = Depends(get_blobs)):
    owner = friend_owner(db, uid, friendId)
    snap = (_today(db, owner) or {}).get("snapshot", [])
    m = re.fullmatch(r"/v1/jobs/([\w-]{8,64})/images/(item-\d{1,2})", snap[index]["image"]) if 0 <= index < len(snap) else None
    return png(blobs, f"users/{owner}/jobs/{m[1]}/{m[2]}.png" if m else None)


class FriendCardBody(BaseModel):
    date: str
    slot: str
    label: str
    color: str


@router.post("/v1/friends/{friendId}/today/items/{index}/card")
def friend_item_card(friendId: str, index: int, body: FriendCardBody, uid: str = Depends(me),  # noqa: N803
                     db: firestore.Client = Depends(get_db)):
    owner = friend_owner(db, uid, friendId)
    now = datetime.now(JST)
    day = now.date().isoformat()
    outfit = _today(db, owner)
    if not outfit:
        raise not_found()
    snapshot = outfit.get("snapshot", [])
    if body.date != day or index < 0 or index >= len(snapshot):
        raise HTTPException(409, {"code": "conflict", "message": "コーデが変わりました。もう一度開いてください"})
    item = snapshot[index]
    if any(item.get(key, "") != getattr(body, key) for key in ("slot", "label", "color")):
        raise HTTPException(409, {"code": "conflict", "message": "コーデが変わりました。もう一度開いてください"})
    image = re.fullmatch(r"/v1/jobs/([\w-]{8,64})/images/(item-\d{1,2})", item.get("image", ""))
    if not image:
        raise not_found()
    charge(db, uid, "nearby", now.date())
    card_id = "c_" + secrets.token_urlsafe(9)
    item_id = "a"
    midnight = datetime.combine(now.date() + timedelta(days=1), datetime.min.time(), JST)
    expires = min(now + CARD_TTL, midnight)
    stored_item = {**garment(item), "image": f"users/{owner}/jobs/{image[1]}/{image[2]}.png",
                   "_id": item.get("itemId", "")}
    db.document(f"cards/{card_id}").set({"owner": owner, "viewer": uid,
        "outfitRef": f"users/{owner}/dailyOutfits/{day}", "expiresAt": expires,
        "image": outfit["image"], "items": {}, "friendId": friendId, "friendIndex": index,
        "friendSnapshot": item, "friendItem": stored_item})
    return {"cardId": card_id, "image": f"/v1/cards/{card_id}/image", "seenAgoSec": 0,
            "expiresAt": expires.isoformat(), "isDemo": False,
            "items": [{**garment(item), "cardItemId": item_id,
                       "image": f"/v1/cards/{card_id}/items/{item_id}/image"}]}


@router.get("/v1/friends/{friendId}/profile-image")
def friend_profile_image(friendId: str, uid: str = Depends(me), db=Depends(get_db), blobs: Blobs = Depends(get_blobs)):  # noqa: N803
    return _jpeg(blobs, f"users/{friend_owner(db, uid, friendId)}/profile.jpg")


@router.get("/v1/friends/requests")
def list_requests(uid: str = Depends(me), db: firestore.Client = Depends(get_db)):
    def bodies(field, other):
        rs = sorted(_requests(db, field, uid), key=lambda s: s.to_dict()["createdAt"], reverse=True)
        return [_request_body(db, s.id, s.to_dict(), s.to_dict()[other]) for s in rs]

    return {"incoming": bodies("to", "from"), "outgoing": bodies("from", "to")}


class RequestBody(BaseModel):
    friendCode: str = Field(max_length=40)


@router.post("/v1/friends/requests", status_code=201)
def send_request(body: RequestBody, uid: str = Depends(me), db: firestore.Client = Depends(get_db)):
    now = datetime.now(JST)
    charge(db, uid, "friend_request", now.date())  # コードの総当たりも止める
    code = re.sub(r"\s", "", body.friendCode).upper()
    to = (db.document(f"friendCodes/{code}").get().to_dict() or {}).get("uid") if re.fullmatch(r"[A-Z0-9]{8}", code) else None
    if not to:
        raise HTTPException(404, {"code": "not_found", "message": "そのフレンドコードの人が見つかりません"})
    if to == uid:
        raise HTTPException(400, {"code": "validation", "message": "自分のフレンドコードです"})
    if any(to in s.to_dict()["members"] for s in _friendships(db, uid)) or any(
            s.to_dict()["to"] == to for s in _requests(db, "from", uid)):
        raise HTTPException(409, {"code": "conflict", "message": "もうフレンドか、申請済みです"})
    crossing = next((s for s in _requests(db, "from", to) if s.to_dict()["to"] == uid), None)
    if crossing:  # 相手が先に申請していた (お互いにコードを読んだ) ので、その場でフレンドになる
        crossing.reference.delete()
        if _befriend(db, to, uid, now)[2]:
            notify.notify_once(db, f"friend_accepted|{uid}|{to}", to, "friend_accepted", f"{_name(db, uid)}さんがフレンドの申請を承認しました")
        return _request_body(db, crossing.id, crossing.to_dict(), to, "accepted")
    rid, r = "r_" + secrets.token_urlsafe(12), {"from": uid, "to": to, "createdAt": now}
    db.document(f"friendRequests/{rid}").set(r)
    notify.notify_once(db, f"friend_request|{uid}|{to}", to, "friend_request", f"{_name(db, uid)}さんからフレンドの申請が届きました", requestId=rid)
    return _request_body(db, rid, r, to)


def _incoming(db, uid: str, rid: str) -> dict:
    r = _doc(db, "friendRequests", rid)
    if not r or r["to"] != uid:
        raise not_found()
    return r


@router.post("/v1/friends/requests/{requestId}/accept")
def accept(requestId: str, uid: str = Depends(me), db: firestore.Client = Depends(get_db)):  # noqa: N803
    r = _incoming(db, uid, requestId)
    fid, f, new = _befriend(db, r["from"], uid, datetime.now(JST))
    db.document(f"friendRequests/{requestId}").delete()
    if new:
        notify.notify_once(db, f"friend_accepted|{uid}|{r['from']}", r["from"], "friend_accepted", f"{_name(db, uid)}さんがフレンドの申請を承認しました")
    return friend_body(db, uid, fid, f)


@router.post("/v1/friends/requests/{requestId}/decline", status_code=204)
def decline(requestId: str, uid: str = Depends(me), db: firestore.Client = Depends(get_db)):  # noqa: N803
    _incoming(db, uid, requestId)
    db.document(f"friendRequests/{requestId}").delete()
    return Response(status_code=204)


@router.delete("/v1/friends/requests/{requestId}", status_code=204)
def cancel(requestId: str, uid: str = Depends(me), db: firestore.Client = Depends(get_db)):  # noqa: N803
    r = _doc(db, "friendRequests", requestId)
    if not r or r["from"] != uid:
        raise not_found()
    db.document(f"friendRequests/{requestId}").delete()
    return Response(status_code=204)


def _jpeg(blobs: Blobs, path: str) -> Response:
    data = blobs.get(path)
    if data is None:
        raise not_found()
    return Response(data, media_type="image/jpeg", headers={"Cache-Control": "private, no-store"})


@router.put("/v1/me/profile-image", status_code=204)
def put_profile_image(image: UploadFile = File(), crop: str | None = Form(None, max_length=500), uid: str = Depends(me),
                      db: firestore.Client = Depends(get_db), blobs: Blobs = Depends(get_blobs)):
    data = image.file.read(MAX_IMAGE + 1)
    try:
        if len(data) > MAX_IMAGE:
            raise ValueError
        im = Image.open(io.BytesIO(data))
        if im.format not in ("JPEG", "MPO", "PNG") or im.width * im.height > MAX_PIXELS:  # 展開する前に止める
            raise ValueError
        im.draft("RGB", (1024, 1024))  # JPEG は縮めて展開する (大きな写真で 512Mi を使い切らないように)
        im = ImageOps.exif_transpose(im).convert("RGB")
        im.thumbnail((1024, 1024))
    except Exception:
        raise HTTPException(400, {"code": "validation", "message": "10MB までの JPEG か PNG にしてください"})
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=90)  # 書き直して EXIF (位置など) を落とす
    blobs.put(f"users/{uid}/profile.jpg", buf.getvalue(), "image/jpeg")
    db.document(f"users/{uid}").set({"profileImage": True} | ({"profileCrop": crop} if crop is not None else {}), merge=True)  # 画像だけ替える時は前の表示範囲を残す
    return Response(status_code=204)


@router.get("/v1/me/profile-image")
def get_profile_image(uid: str = Depends(me), blobs: Blobs = Depends(get_blobs)):
    return _jpeg(blobs, f"users/{uid}/profile.jpg")


@router.delete("/v1/me/profile-image", status_code=204)
def delete_profile_image(uid: str = Depends(me), db: firestore.Client = Depends(get_db), blobs: Blobs = Depends(get_blobs)):
    blobs.delete(f"users/{uid}/profile.jpg")
    db.document(f"users/{uid}").set({"profileImage": False, "profileCrop": None}, merge=True)
    return Response(status_code=204)
