"""通知の一覧と既読 (GET /v1/notifications、POST /v1/notifications/read)、端末の登録 (PUT/DELETE /v1/me/devices)。

通知を作るのは notify.notify。匿名 (Web デモ) も自分の uid で使う。
"""
import re

from fastapi import APIRouter, Depends, Response
from google.cloud import firestore
from pydantic import BaseModel, Field

from auth import User, current_user
from notify import device_id
from routes_me import get_db, today_jst

router = APIRouter()
NOTE_RE = re.compile(r"[A-Za-z0-9_-]{1,40}")
REF_KEYS = ("requestId", "jobId")


class DeviceBody(BaseModel):
    token: str = Field(min_length=1, max_length=4096)


@router.put("/v1/me/devices", status_code=204)
def put_device(body: DeviceBody, user: User = Depends(current_user), db: firestore.Client = Depends(get_db)):
    """端末は最後に登録したアカウントだけのもの (deviceOwners/{id})。入り直す前のアカウントの通知を届けない。"""
    did = device_id(body.token)
    owner = db.document(f"deviceOwners/{did}")
    prev = (owner.get().to_dict() or {}).get("uid")
    if prev and prev != user.uid:
        db.document(f"users/{prev}/devices/{did}").delete()
    owner.set({"uid": user.uid})
    db.document(f"users/{user.uid}/devices/{did}").set({"token": body.token, "at": firestore.SERVER_TIMESTAMP})
    return Response(status_code=204)


@router.delete("/v1/me/devices", status_code=204)
def delete_device(body: DeviceBody, user: User = Depends(current_user), db: firestore.Client = Depends(get_db)):
    db.document(f"users/{user.uid}/devices/{device_id(body.token)}").delete()
    return Response(status_code=204)


def _unread_q(db, uid: str):
    return db.collection(f"users/{uid}/notifications").where(filter=firestore.FieldFilter("read", "==", False))


def _unread_count(db, uid: str) -> int:
    return int(_unread_q(db, uid).count().get()[0][0].value)


def me_fields(db, uid: str) -> dict:
    """/v1/me に足す 2 つ (routes_me.me_body がつなぐ)。"""
    day = db.document(f"users/{uid}/dailyOutfits/{today_jst()}").get().to_dict() or {}
    return {"likeCountToday": day.get("likeCount", 0), "unreadNotifications": _unread_count(db, uid)}


@router.get("/v1/notifications")
def list_notifications(user: User = Depends(current_user), db: firestore.Client = Depends(get_db)):
    q = db.collection(f"users/{user.uid}/notifications").order_by("createdAt", direction=firestore.Query.DESCENDING).limit(50)
    items = []
    for s in q.stream():
        d = s.to_dict()
        items.append({"id": s.id, "type": d["type"], "text": d["text"], "createdAt": d["createdAt"].isoformat(),
                      "read": d.get("read", False), **{k: d[k] for k in REF_KEYS if k in d}})
    return {"items": items, "unread": _unread_count(db, user.uid)}


class ReadBody(BaseModel):
    ids: list[str] | None = Field(None, max_length=500)


@router.post("/v1/notifications/read", status_code=204)
def read(body: ReadBody, user: User = Depends(current_user), db: firestore.Client = Depends(get_db)):
    if body.ids is None:
        refs = [s.reference for s in _unread_q(db, user.uid).stream()]
    else:
        ids = [i for i in body.ids if NOTE_RE.fullmatch(i)]
        refs = [s.reference for s in db.get_all([db.document(f"users/{user.uid}/notifications/{i}") for i in ids]) if s.exists]
    for n in range(0, len(refs), 400):  # 1 回の batch は 500 件まで
        batch = db.batch()
        for r in refs[n:n + 400]:
            batch.update(r, {"read": True})
        batch.commit()
    return Response(status_code=204)
