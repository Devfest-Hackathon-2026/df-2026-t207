"""見る側のカード (cards/{cardId}): 確かめ、カードの画像 (透かしは 2026-11-08 にやめた)、ブロック、通報、Web デモの模擬の検出。

照合と着用イメージも load_card でカードを確かめる。
"""
import hmac
import os
import re
from datetime import datetime
from typing import Literal

from fastapi import APIRouter, Depends, Header, HTTPException, Response
from google.cloud import firestore
from pydantic import BaseModel, Field

from auth import User, charge_user, current_user
from blobs import Blobs, get_blobs
from routes_me import JST, get_db

router = APIRouter()
CARD_RE = re.compile(r"c_[A-Za-z0-9_-]{1,40}")


def not_found() -> HTTPException:  # 毎回作る (使い回すと __traceback__ が伸び続け、前の要求の写真を抱え込む)
    return HTTPException(404, {"code": "not_found", "message": "見つかりません"})


def load_card(db, card_id: str, viewer_uid: str, now: datetime) -> dict:
    """見る人本人のカードを返す。無い・他人のカードは 404 (在ることも教えない)。
    期限切れと、持ち主が公開をやめた時は 410 (デモの人物は公開の状態を見ない)。"""
    d = db.document(f"cards/{card_id}").get().to_dict() if CARD_RE.fullmatch(card_id) else None
    if not d or d.get("viewer") != viewer_uid:
        raise not_found()
    if friend_id := d.get("friendId"):
        friendship = db.document(f"friendships/{friend_id}").get().to_dict() or {}
        members = friendship.get("members", [])
        outfit = db.document(d["outfitRef"]).get().to_dict() or {}
        snapshot = outfit.get("snapshot", [])
        index = d.get("friendIndex", -1)
        if (viewer_uid not in members or d["owner"] not in members or
                not d["outfitRef"].endswith("/" + now.astimezone(JST).date().isoformat()) or
                outfit.get("visibility") != "nearby" or outfit.get("image") != d.get("image") or
                not 0 <= index < len(snapshot) or snapshot[index] != d.get("friendSnapshot")):
            raise HTTPException(410, {"code": "card_expired", "message": "フレンドのコーデをもう一度開いてください"})
    gone = now >= d["expiresAt"] or (
        not d.get("demo") and (db.document(d["outfitRef"]).get().to_dict() or {}).get("visibility") != "nearby")
    if gone:
        message = ("フレンドのコーデをもう一度開いてください" if d.get("friendId") else
                   "表示の期限が切れました。もう一度近くの人を探してください")
        raise HTTPException(410, {"code": "card_expired", "message": message})
    return d


def _now() -> datetime:
    return datetime.now(JST)


def _card_png(blobs: Blobs, path: str | None) -> Response:
    data = blobs.get(path) if path else None
    if data is None:
        raise not_found()
    # 透かしは入れない (2026-11-08 チームの判断)。画面の保存は Android で止め、カードは 30 分で切れ、本人にだけ保存させない指定で返す
    return Response(data, media_type="image/png", headers={"Cache-Control": "private, no-store"})


@router.get("/v1/cards/{cardId}/image")
def card_image(cardId: str, user: User = Depends(current_user), db=Depends(get_db), blobs: Blobs = Depends(get_blobs)):  # noqa: N803
    card = load_card(db, cardId, user.uid, _now())
    return _card_png(blobs, card.get("image"))  # 作った時の着姿 (登録し直した後の物は見せない)


@router.get("/v1/cards/{cardId}/items/{cardItemId}/image")
def card_item_image(cardId: str, cardItemId: str, user: User = Depends(current_user), db=Depends(get_db),  # noqa: N803
                    blobs: Blobs = Depends(get_blobs)):
    card = load_card(db, cardId, user.uid, _now())
    if card.get("friendId"):
        return _card_png(blobs, card.get("friendItem", {}).get("image") if cardItemId == "a" else None)
    wid = card["items"].get(cardItemId)
    w = (db.document(f"users/{card['owner']}/wardrobeItems/{wid}").get().to_dict() or {}) if wid else {}
    return _card_png(blobs, w.get("image"))


class CardBody(BaseModel):
    cardId: str


class ReportBody(CardBody):
    reason: Literal["inappropriate", "not_clothes", "harassment", "other"]
    note: str = Field("", max_length=200)


@router.post("/v1/blocks", status_code=204)
def block(body: CardBody, user: User = Depends(current_user), db: firestore.Client = Depends(get_db)):
    card = load_card(db, body.cardId, user.uid, _now())
    if not card.get("demo"):  # デモの人物は記録しない (審査員がその人を二度と見られなくなるため)
        db.document(f"blocks/{user.uid}_{card['owner']}").set({"at": firestore.SERVER_TIMESTAMP})
    return Response(status_code=204)


@router.post("/v1/reports", status_code=204)
def report(body: ReportBody, user: User = Depends(current_user), db: firestore.Client = Depends(get_db)):
    card = load_card(db, body.cardId, user.uid, _now())
    db.collection("reports").add({"owner": card["owner"], "reporter": user.uid, "outfitRef": card["outfitRef"],
                                  "reason": body.reason, "note": body.note, "at": firestore.SERVER_TIMESTAMP})
    return Response(status_code=204)


@router.post("/v1/demo/nearby")
def demo_nearby(user: User = Depends(current_user), db: firestore.Client = Depends(get_db)):
    """模擬の検出。デモ用の架空の人物 (WEB_DEMO_UIDS) のカードを返す。Web の審査員と、実機無しで試すアプリの両方が使う。"""
    from nearby import _outfit, blocked, make_card

    now = _now()
    charge_user(db, user, "nearby", now.date())
    cards = []
    for owner in [u for u in os.environ.get("WEB_DEMO_UIDS", "").split(",") if u]:  # 壇上の本人は DEMO_UIDS だけに入れ、ここには入れない
        ref, outfit = _outfit(db, owner, None, True)
        if outfit and outfit.get("image") and not blocked(db, user.uid, owner):
            cards.append(make_card(db, user.uid, owner, ref, outfit, now, now, True))
    return {"cards": cards, "viewerPublishing": True}


@router.post("/v1/admin/demo/reset", status_code=204)
def demo_reset(x_admin_token: str = Header("")):
    """デモ用の人物は 1 日 1 回の記録 (viewLog) を書かない作りなので、消す物は無い。合言葉だけ確かめて 204 を返す。"""
    expected = os.environ.get("ADMIN_TOKEN", "")
    if not expected or not hmac.compare_digest(x_admin_token.encode(), expected.encode()):
        raise HTTPException(401, {"code": "unauthenticated", "message": "管理用の合言葉が違います"})
    return Response(status_code=204)
