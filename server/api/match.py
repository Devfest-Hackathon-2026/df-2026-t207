"""見た服を手持ちと照合する (POST /v1/match、tasks の S3)。事前の結果 (S6) の引き方は着用イメージと共有する。

- 見る人本人のカードだけ (load_card)。手持ちと写真は acting_uid の物、回数は本人の uid
- Gemini が返した id は、渡した一覧に在る物だけ残す
- 事前の結果 (precomputed/{kind}_{見る人}_{owner}_{itemId}...、D3 が作る) は、名前に入れた見る人の手持ちと写真で作った物。
  名前に見る人 (acting_uid) を入れるので、他人の手持ちで作った結果は返らない。
  返すのは AI_DISABLED=1 の時だけ。デモの人物でも普段はその場で作る (2026-11-10 白井さん、事前の物を今作った物に見せないため)
"""
import logging
import os
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from google.cloud import firestore
from pydantic import BaseModel

import ai
from auth import User, acting_uid, charge_user, current_user
from blobs import Blobs, get_blobs
from cards import load_card, not_found
from nearby import garment
from routes_me import JST, get_db

MAX_CANDIDATES = 30
# 見た服と一緒に着ない区分 (書いていない区分は同じ区分だけ)。手持ちは全部 Gemini に渡し (似た服を探すため)、組み合わせからだけ外す
CLASH = {"dress": {"dress", "top", "bottom"}, "top": {"top", "dress"}, "bottom": {"bottom", "dress"}}
router = APIRouter()


def ai_off() -> HTTPException:
    return HTTPException(503, {"code": "ai_disabled", "message": "今は AI を止めています"})


BUSY_WAITS = (3, 8)  # 429 (混んでいる) の時に待つ秒数。画像の生成は 1 本ずつでもすぐ 429 になる


def call_ai(fn, *args):
    """Gemini を呼ぶ。429 と 503 は少し待ってやり直す。止めている時は 503、応答が無い・形が違う・安全の判定で止まった時は 502 (中身はログに出さない)。"""
    for wait in (*BUSY_WAITS, None):
        try:
            return fn(*args)
        except ai.AiDisabled:
            raise ai_off()
        except Exception as e:
            if wait is not None and any(code in str(e) for code in ("429", "503")):  # 混雑と一時的な障害は待ってやり直す
                time.sleep(wait)
                continue
            logging.error("ai call failed: %s", type(e).__name__)
            raise HTTPException(502, {"code": "internal", "message": "AI の応答を受け取れませんでした。もう一度お試しください"})


def seen_item(db, user: User, card_id: str, card_item_id: str, now: datetime) -> tuple[dict, str]:
    """カードの服の文書と持ち主を返す。無ければ 404、期限切れは 410。"""
    card = load_card(db, card_id, user.uid, now)
    if card.get("friendId"):
        if card_item_id != "a" or not card.get("friendItem"):
            raise not_found()
        return card["friendItem"], card["owner"]
    wid = card["items"].get(card_item_id)
    item = db.document(f"users/{card['owner']}/wardrobeItems/{wid}").get().to_dict() if wid else None
    if not item:
        raise not_found()
    return {**item, "_id": wid}, card["owner"]


def precomputed(db, kind: str, me: str, owner: str, rest: list[str]) -> dict | None:
    """AI を止めている時だけ使う事前の結果 (precomputed/{kind}_{me}_{owner}_{rest...})。止めていなければ None、止めていて無ければ 503。

    デモの人物でも普段はその場で作る。事前の結果を今作った物に見せないため (2026-11-10 白井さん)。返す時は precomputed: true を付け、画面に出す。"""
    if os.environ.get("AI_DISABLED") != "1":
        return None
    if d := db.document("precomputed/" + "_".join([kind, me, owner, *rest])).get().to_dict():
        return d
    raise ai_off()


class MatchBody(BaseModel):
    cardId: str
    cardItemId: str


@router.post("/v1/match")
def match(body: MatchBody, user: User = Depends(current_user), db: firestore.Client = Depends(get_db),
          blobs: Blobs = Depends(get_blobs)):
    now = datetime.now(JST)
    item, owner = seen_item(db, user, body.cardId, body.cardItemId, now)
    me = acting_uid(user)
    seen = {**garment(item), "cardItemId": body.cardItemId, "image": f"/v1/cards/{body.cardId}/items/{body.cardItemId}/image"}
    pre = precomputed(db, "match", me, owner, [item["_id"]])
    if pre:
        return {"seen": seen, **{k: pre.get(k) for k in ("combos", "missing", "similarOwned")}, "precomputed": True}

    seen_png = blobs.get(item.get("image", ""))
    if seen_png is None:
        raise not_found()
    charge_user(db, user, "match", now.date())
    return {"seen": seen, **run_match(db, blobs, me, item, seen_png, lambda *a: call_ai(ai.ask_match, *a)), "precomputed": False}


def run_match(db, blobs: Blobs, me: str, item: dict, seen_png: bytes, ask=ai.ask_match) -> dict:
    """me の手持ちと照合し、combos・missing・similarOwned を返す。api と事前の結果を作るスクリプト (D3) が共有する。"""
    clash = CLASH.get(item.get("slot"), {item.get("slot")})
    mine = [(s.id, s.to_dict()) for s in db.collection(f"users/{me}/wardrobeItems").stream()]
    mine.sort(key=lambda m: m[1].get("createdAt") or datetime.min.replace(tzinfo=JST), reverse=True)
    mine = mine[:MAX_CANDIDATES]
    with ThreadPoolExecutor(8) as ex:  # 30 枚を 1 枚ずつ取ると、Gemini の前に数秒かかる
        pngs = list(ex.map(lambda m: blobs.get(m[1].get("image", "")), mine))
    candidates = [(wid, garment(d), png) for (wid, d), png in zip(mine, pngs) if png is not None]
    out = ask(garment(item), seen_png, candidates)
    ids = {c[0] for c in candidates}
    wearable = {wid for wid, g, _ in candidates if g.get("slot") not in clash}
    similar = out.get("similarOwned")
    return {
        "combos": [c for c in out.get("combos", [])  # 着用イメージに渡せるのは手持ち 3 着まで
                   if 0 < len(c["wardrobeItemIds"]) <= 3 and set(c["wardrobeItemIds"]) <= wearable][:3],
        "missing": out.get("missing"),
        "similarOwned": similar if similar and similar.get("wardrobeItemId") in ids else None,
    }
