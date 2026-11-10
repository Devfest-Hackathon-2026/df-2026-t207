"""見た服の保存 (GET/POST /v1/saves、DELETE /v1/saves/{saveId})。tasks の M9。

保存するのは服の情報 (nearby.garment の項目) だけ。着姿と切り抜きの画像 (path も)、誰の服か、cardId は残さない。
source は nearby か friend だけ。カードの期限の後も残る。匿名 (Web デモ) もカードからは保存できる。
"""
import re
import secrets
from datetime import datetime

from fastapi import APIRouter, Depends, Response
from google.cloud import firestore
from pydantic import BaseModel, Field

import friends
from auth import User, charge_user, current_user, google_uid
from cards import not_found
from match import seen_item
from nearby import garment
from routes_me import JST, get_db

router = APIRouter()
SAVE_RE = re.compile(r"s_[A-Za-z0-9_-]{1,40}")


class FromCard(BaseModel):
    cardId: str
    cardItemId: str


class FromFriend(BaseModel):
    friendId: str
    index: int = Field(ge=0)


def _body(d: dict, save_id: str) -> dict:
    return {**garment(d), "saveId": save_id, "savedAt": d["savedAt"].isoformat(), "source": d["source"]}


@router.post("/v1/saves", status_code=201)
def save(body: FromCard | FromFriend, user: User = Depends(current_user), db: firestore.Client = Depends(get_db)):
    now = datetime.now(JST)
    if isinstance(body, FromCard):
        item, _ = seen_item(db, user, body.cardId, body.cardItemId, now)
        source = "nearby"
    else:
        owner = friends.friend_owner(db, google_uid(user), body.friendId)
        snap = (friends._today(db, owner) or {}).get("snapshot", [])  # FriendPost.items と同じ順
        if body.index >= len(snap):
            raise not_found()
        item, source = snap[body.index], "friend"
    charge_user(db, user, "save", now.date())
    save_id = "s_" + secrets.token_urlsafe(9)
    doc = {**garment(item), "source": source, "savedAt": now}
    db.document(f"users/{user.uid}/saves/{save_id}").set(doc)
    return _body(doc, save_id)


@router.get("/v1/saves")
def list_saves(user: User = Depends(current_user), db: firestore.Client = Depends(get_db)):
    q = db.collection(f"users/{user.uid}/saves").order_by("savedAt", direction=firestore.Query.DESCENDING)
    return {"items": [_body(s.to_dict(), s.id) for s in q.stream()]}


@router.delete("/v1/saves/{saveId}", status_code=204)
def delete_save(saveId: str, user: User = Depends(current_user), db: firestore.Client = Depends(get_db)):  # noqa: N803
    if SAVE_RE.fullmatch(saveId):
        db.document(f"users/{user.uid}/saves/{saveId}").delete()
    return Response(status_code=204)
