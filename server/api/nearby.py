"""受け取った匿名 ID を、近くのコーデのカードに変える (POST /v1/nearby、tasks の S1)。

安全の決まり (docs/architecture.md の 3.3、5 節):
- 見る人も今日公開している時だけ返す (お互いさま)
- 同じ人の着姿は見る人ごとに 1 日 1 回。記録は HMAC の値だけ
- 返すのは使い捨ての cardId と、カードの中だけの cardItemId。uid・匿名 ID・手持ちの服の id は返さない
- DEMO_UIDS の人は、日付・1 日 1 回・お互いさまの判定から外す
"""
import hashlib
import hmac
import os
import re
import secrets
from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException
from google.api_core.exceptions import AlreadyExists
from google.cloud import firestore
from pydantic import AwareDatetime, BaseModel, Field

from auth import User, charge, current_user, google_uid
from routes_me import JST, get_db

GRACE = timedelta(minutes=20)  # 枠が終わってから受け付ける時間 (画面オフで交換が遅れるため)
CARD_TTL = timedelta(minutes=30)
ID_RE = re.compile(r"[0-9a-f]{22}")
GARMENT_KEYS = ("slot", "category", "label", "layer", "color", "pattern", "materialGuess")
router = APIRouter()


def garment(d: dict) -> dict:
    return {k: d[k] for k in GARMENT_KEYS if k in d}


def blocked(db, a: str, b: str) -> bool:
    """どちらかがどちらかをブロックしていれば True。"""
    return any(s.exists for s in db.get_all([db.document(f"blocks/{a}_{b}"), db.document(f"blocks/{b}_{a}")]))


def _outfit(db, uid: str, day: str, demo: bool):
    if not demo:
        doc = db.document(f"users/{uid}/dailyOutfits/{day}").get()
        data = doc.to_dict() or {}
        return doc.reference, data if data.get("visibility") == "nearby" else None
    from routes_me import demo_today  # デモの人は日付に依らず、画像の有る一番新しいコーデ (Web の審査員の自分と同じ選び方)

    day, outfit = demo_today(db, uid)
    return (db.document(f"users/{uid}/dailyOutfits/{day}"), outfit) if outfit else (None, None)


def _first_view_today(db, secret: bytes, viewer: str, owner: str, day: str) -> bool:
    key = hmac.new(secret, f"{viewer}|{owner}|{day}".encode(), hashlib.sha256).hexdigest()
    try:
        db.document(f"viewLog/{day}/v/{key}").create({"at": firestore.SERVER_TIMESTAMP})
        return True
    except AlreadyExists:  # 既にある = 今日もう見た
        return False


def resolve(db, viewer: str, sightings: list[dict], now: datetime, demo_uids: set[str], secret: bytes) -> dict:
    today = now.astimezone(JST).date().isoformat()
    me = db.document(f"users/{viewer}/dailyOutfits/{today}").get().to_dict() or {}
    if me.get("visibility") != "nearby":  # 見る人がデモでも、お互いさまと 1 日 1 回は外さない
        return {"cards": [], "viewerPublishing": False}

    # ID → 持ち主。同じ持ち主の ID は 1 つにまとめ、一番新しい受信と一番強い電波を残す
    best: dict[str, dict] = {}
    ok = [s for s in sightings if isinstance(s.get("id"), str) and ID_RE.fullmatch(s["id"])]
    found = {d.id: d.to_dict() for d in db.get_all([db.document(f"broadcastIds/{s['id']}") for s in ok]) if d.exists}
    gens: dict[str, str | None] = {}
    for s in ok:
        b = found.get(s["id"])
        if not b:
            continue
        owner = b["uid"]
        if owner not in gens:
            gens[owner] = (db.document(f"users/{owner}").get().to_dict() or {}).get("publishGen")
        if owner == viewer or now > b["slotEnd"] + GRACE or b.get("gen") != gens[owner]:
            continue
        seen = datetime.fromisoformat(s["lastSeenAt"])
        rssi = s.get("rssi")
        key = (seen, -127 if rssi is None else rssi)  # rssi の無い報告は一番弱い扱い (None と数は比べられない)
        if owner not in best or key > best[owner]["key"]:
            best[owner] = {"key": key, "seen": seen, "date": b["date"]}

    cards = []
    for owner, hit in sorted(best.items(), key=lambda kv: kv[1]["key"], reverse=True):
        demo = owner in demo_uids
        ref, outfit = _outfit(db, owner, hit["date"], demo)
        if outfit is None or blocked(db, viewer, owner):
            continue
        # 1 日 1 回から外す本物の人 (壇上の A など)。デモの人物と違い「AI 生成」の印は付けない
        exempt = owner in os.environ.get("ONCE_A_DAY_EXEMPT_UIDS", "").split(",")
        if not demo and not exempt and not _first_view_today(db, secret, viewer, owner, today):
            continue
        cards.append(make_card(db, viewer, owner, ref, outfit, hit["seen"], now, demo))
    return {"cards": cards, "viewerPublishing": True}


def make_card(db, viewer: str, owner: str, ref, outfit: dict, seen: datetime, now: datetime, demo: bool) -> dict:
    """使い捨てのカードを作って cards に置き、見る側に返す形にする。手持ちの id は cards の中にだけ持つ。"""
    card_id = "c_" + secrets.token_urlsafe(9)
    wids = outfit.get("items", [])
    found = {s.id: s.to_dict() for s in db.get_all([db.document(f"users/{owner}/wardrobeItems/{w}") for w in wids]) if s.exists}
    item_map, items = {}, []
    for n, wid in enumerate(w for w in wids if w in found):  # 手持ちから外した服は出さない
        cid = chr(ord("a") + n)
        item_map[cid] = wid
        items.append({**garment(found[wid]), "cardItemId": cid, "image": f"/v1/cards/{card_id}/items/{cid}/image"})
    expires = now + CARD_TTL
    db.document(f"cards/{card_id}").set({"owner": owner, "viewer": viewer, "outfitRef": ref.path, "expiresAt": expires,
                                         "items": item_map, "image": outfit.get("image"), "demo": demo})
    ref.update({"viewCount": firestore.Increment(1)})
    return {
        "cardId": card_id,
        "image": f"/v1/cards/{card_id}/image",
        "seenAgoSec": max(0, int((now - seen).total_seconds())),
        "expiresAt": expires.isoformat(),
        "isDemo": demo,
        "items": items,
    }


class Sighting(BaseModel):
    id: str = Field(pattern=r"^[0-9a-f]{22}$")
    lastSeenAt: AwareDatetime
    rssi: int | None = None
    txPower: int | None = None


class NearbyBody(BaseModel):
    sightings: list[Sighting] = Field(max_length=200)


@router.post("/v1/nearby")
def nearby(body: NearbyBody, user: User = Depends(current_user), db: firestore.Client = Depends(get_db)):
    google_uid(user)
    secret = os.environ["VIEWLOG_SECRET"].encode()  # 回数を引く前に読む (無ければここで落ちる)
    now = datetime.now(JST)
    charge(db, user.uid, "nearby", now.date())
    demo = {u for u in os.environ.get("DEMO_UIDS", "").split(",") if u}
    return resolve(db, user.uid, [s.model_dump(mode="json") for s in body.sightings], now, demo, secret)
