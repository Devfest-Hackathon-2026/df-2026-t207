"""今日の公開と匿名 ID の発行 (PUT /v1/publish、tasks の S1)。

公開した時に、その時刻の 5 分の枠からその日の 24 時 (JST) までの ID をまとめて発行する。
公開ごとに世代 (publishGen) を変え、ID にも同じ世代を付ける。nearby は最新の世代の ID だけを通すので、
公開し直した・取り消した後の古い ID は、消し損ねても (同時に 2 回押しても) 通らない。古い ID は掃除として消す。
"""
import os
import secrets
from datetime import datetime, timedelta
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from google.cloud import firestore
from pydantic import BaseModel

from auth import User, current_user, google_uid
from routes_me import JST, get_db

SLOT = timedelta(minutes=5)
router = APIRouter()


def _midnight_after(now: datetime) -> datetime:
    return datetime.combine(now.date() + timedelta(days=1), datetime.min.time(), JST)


def _drop_ids(db: firestore.Client, uid: str, day: str) -> None:
    old = db.collection("broadcastIds").where(filter=firestore.FieldFilter("uid", "==", uid)).where(
        filter=firestore.FieldFilter("date", "==", day)
    )
    refs = [d.reference for d in old.stream()]
    for i in range(0, len(refs), 400):  # batch の上限 500 より小さく区切る
        batch = db.batch()
        for r in refs[i : i + 400]:
            batch.delete(r)
        batch.commit()


def issue_ids(db: firestore.Client, uid: str, now: datetime) -> list[dict]:
    """now の枠から 24 時までの枠ごとに 11 バイトの ID を作り、新しい世代を付けて broadcastIds に置く。"""
    day = now.date().isoformat()
    _drop_ids(db, uid, day)
    gen = secrets.token_hex(8)
    start = now.replace(minute=now.minute - now.minute % 5, second=0, microsecond=0)
    end = _midnight_after(now)
    out, batch, t = [], db.batch(), start
    while t < end:
        bid = secrets.token_hex(11)
        batch.set(db.document(f"broadcastIds/{bid}"), {"uid": uid, "date": day, "gen": gen, "slotStart": t, "slotEnd": t + SLOT})
        out.append({"slotStart": t.isoformat(), "id": bid})
        t += SLOT
    batch.commit()  # 1 日 288 個まで。1 回の batch の上限 500 に収まる
    db.document(f"users/{uid}").set({"publishGen": gen}, merge=True)  # ID を置いた後に世代を切り替える
    return out


class PublishBody(BaseModel):
    visibility: Literal["nearby", "private"]


@router.put("/v1/publish")
def publish(body: PublishBody, user: User = Depends(current_user), db: firestore.Client = Depends(get_db)):
    google_uid(user)
    now = datetime.now(JST)
    day = now.date().isoformat()
    ref = db.document(f"users/{user.uid}/dailyOutfits/{day}")
    if body.visibility == "private":
        db.document(f"users/{user.uid}").set({"publishGen": firestore.DELETE_FIELD}, merge=True)
        _drop_ids(db, user.uid, day)
        if ref.get().exists:
            ref.set({"visibility": "private"}, merge=True)
        return {"visibility": "private"}
    demo = user.uid in os.environ.get("DEMO_UIDS", "").split(",")
    if not demo and not ref.get().exists:  # デモの人は日付を問わず一番新しい着姿を使う (nearby)
        raise HTTPException(409, {"code": "no_outfit_today", "message": "先に今日のコーデを登録してください"})
    until = _midnight_after(now).isoformat()
    ids = issue_ids(db, user.uid, now)
    ref.set({"visibility": "nearby", "until": until}, merge=True)
    return {"visibility": "nearby", "until": until, "broadcastIds": ids}
