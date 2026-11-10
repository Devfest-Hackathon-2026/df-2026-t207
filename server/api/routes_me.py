"""自分の状態 (GET/PATCH /v1/me)。"""
from datetime import datetime, timedelta, timezone
import os
from functools import lru_cache


from fastapi import APIRouter, Depends
from google.cloud import firestore
from pydantic import BaseModel, Field

from auth import User, current_user, google_uid

JST = timezone(timedelta(hours=9))  # 日本は夏時間が無い (Windows に tzdata が無くても動く)
router = APIRouter()


@lru_cache
def get_db() -> firestore.Client:
    return firestore.Client()


def today_jst() -> str:
    return datetime.now(JST).date().isoformat()


def demo_today(db: firestore.Client, uid: str) -> tuple[str, dict]:
    """デモの人物の「今日のコーデ」= 一番新しい日のコーデ (日付, 文書)。凍結の後もデータを足さずに見せるため、日付に依らない"""
    # 件数は数件なので全部読む (Firestore は文書 id の降順で引けない)。画像の無い記録 (手で足した物など) は飛ばす
    for d in sorted(db.collection(f"users/{uid}/dailyOutfits").stream(), key=lambda d: d.id, reverse=True):
        if (data := d.to_dict() or {}).get("image"):
            return d.id, data
    return today_jst(), {}


def me_body(db: firestore.Client, user: User) -> dict:
    # Web デモの審査員 (匿名) は、今日のコーデを公開しているデモの見る人として見せる (2026-11-10 白井さん)
    demo = user.is_anonymous and os.environ.get("DEMO_VIEWER_UID")
    uid = demo or user.uid
    prof = db.collection("users").document(uid).get().to_dict() or {}
    if demo:
        day = demo_today(db, uid)[1]
        tomorrow = datetime.combine(datetime.now(JST).date() + timedelta(days=1), datetime.min.time(), JST)
        publishing = {"visibility": "nearby", "until": tomorrow.isoformat()} if day else {"visibility": "private"}
    else:
        day = db.collection("users").document(uid).collection("dailyOutfits").document(today_jst()).get().to_dict() or {}
        publishing = {"visibility": day.get("visibility", "private")}
        if day.get("until"):
            publishing["until"] = day["until"]
    return {
        "uid": user.uid,
        "displayName": prof.get("displayName", ""),
        "isAnonymous": user.is_anonymous,
        "publishing": publishing,
        "viewCountToday": day.get("viewCount", 0),
        "hasPhoto": prof.get("hasPhoto", False),
    } | social_fields(db, user)


def social_fields(db: firestore.Client, user: User) -> dict:
    """フレンドコード・プロフィール画像 (匿名には作らない) と、いいねの数・未読の通知の数。"""
    import friends
    import notifications

    return ({} if user.is_anonymous else friends.me_fields(db, user.uid)) | notifications.me_fields(db, user.uid)


class MePatch(BaseModel):
    displayName: str = Field(min_length=1, max_length=20)


@router.get("/v1/me")
def get_me(user: User = Depends(current_user), db: firestore.Client = Depends(get_db)):
    return me_body(db, user)


@router.patch("/v1/me")
def patch_me(body: MePatch, user: User = Depends(current_user), db: firestore.Client = Depends(get_db)):
    google_uid(user)  # Web デモの審査員は Demo のまま (名前を書き換えさせない)
    db.collection("users").document(user.uid).set({"displayName": body.displayName}, merge=True)
    return me_body(db, user)
