"""Firebase の ID トークンの検証と、1 日の回数の上限 (tasks の S5)。"""
import os
from dataclasses import dataclass
from datetime import date

from fastapi import Header, HTTPException
from google.cloud import firestore

DEFAULT_QUOTA = {"nearby": 200, "match": 30, "tryon": 10, "same": 30, "friend_request": 50, "like": 200, "save": 100}
# 匿名 (Web デモの審査員) は全員で 1 つの枠。ログインし直せば作れる uid ごとに数えると、上限にならないため
ANON_KEY = "anonymous"
ANON_QUOTA = {"nearby": 5000, "match": 100, "tryon": 30, "like": 2000, "save": 1000}
# 匿名の 1 人ごとの枠も置く。全員の枠だけだと、1 人が使い切ると審査員全員が止まるため (2026-11-10 白井さん)
ANON_EACH_QUOTA = {"nearby": 300, "match": 50, "tryon": 40, "like": 200, "save": 100}


@dataclass
class User:
    uid: str
    is_anonymous: bool


def _verify(token: str) -> dict:
    import firebase_admin
    from firebase_admin import auth

    if not firebase_admin._apps:
        firebase_admin.initialize_app()
    return auth.verify_id_token(token)


async def current_user(authorization: str = Header("")) -> User:
    if not authorization.startswith("Bearer "):
        raise HTTPException(401, {"code": "unauthenticated", "message": "ログインしてください"})
    try:
        decoded = _verify(authorization[len("Bearer ") :])
    except Exception:
        raise HTTPException(401, {"code": "unauthenticated", "message": "ログインし直してください"})
    return User(decoded["uid"], decoded.get("firebase", {}).get("sign_in_provider") == "anonymous")


def google_uid(user: User) -> str:
    """書き込みと本物の検出は Google でログインした人だけ。"""
    if user.is_anonymous:
        raise HTTPException(403, {"code": "forbidden", "message": "Google でログインしてください"})
    return user.uid


def quota_key(user: User) -> str:
    return ANON_KEY if user.is_anonymous else user.uid


def acting_uid(user: User) -> str:
    """誰の手持ちと写真を使うか。匿名 (Web デモの審査員) はデモの見る人 (DEMO_VIEWER_UID) として動く。"""
    if not user.is_anonymous:
        return user.uid
    demo = os.environ.get("DEMO_VIEWER_UID")
    if not demo:
        raise HTTPException(403, {"code": "forbidden", "message": "Google でログインしてください"})
    return demo


def charge(db: firestore.Client, uid: str, kind: str, today: date) -> None:
    """その日の kind の回数を 1 足す。上限を超えたら 429。"""
    if uid == ANON_KEY:
        limit = int(os.environ.get(f"QUOTA_ANON_{kind.upper()}", ANON_QUOTA.get(kind, 100)))
    else:
        limit = int(os.environ.get(f"QUOTA_{kind.upper()}", DEFAULT_QUOTA.get(kind, 50)))
    _bump(db, uid, kind, today, limit)


def charge_user(db: firestore.Client, user: User, kind: str, today: date) -> None:
    """匿名なら 1 人ごとの枠を先に数え (超えた分は全員の枠を減らさない)、それから全員の枠を数える。Google の人は本人の枠。"""
    if user.is_anonymous:
        each = int(os.environ.get(f"QUOTA_ANON_EACH_{kind.upper()}", ANON_EACH_QUOTA.get(kind, 50)))
        _bump(db, f"anon-each-{user.uid}", kind, today, each)
    charge(db, quota_key(user), kind, today)


def _bump(db: firestore.Client, key: str, kind: str, today: date, limit: int) -> None:
    ref = db.collection("quotas").document(f"{key}_{today.isoformat()}")

    @firestore.transactional
    def bump(tx):
        used = (ref.get(transaction=tx).to_dict() or {}).get(kind, 0)
        if used >= limit:
            raise HTTPException(429, {"code": "quota_exceeded", "message": "今日の回数の上限に達しました"})
        tx.set(ref, {kind: used + 1}, merge=True)

    bump(db.transaction())
