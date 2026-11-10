"""通知を作る部品 (docs/api.yaml の Notification)。フレンド・いいね・処理の完了から呼ぶ。

users/{uid}/notifications に置き (アプリの一覧と既読の同期はここを読む)、users/{uid}/devices の FCM トークンへプッシュする。
プッシュに載せるのは種類と短い文だけ (着姿の画像や相手の uid は載せない)。プッシュが落ちても通知は残し、例外は外に出さない。
"""
import hashlib
import logging
from datetime import datetime, timedelta, timezone

from google.api_core.exceptions import AlreadyExists
from google.cloud import firestore


def device_id(token: str) -> str:
    """users/{uid}/devices の文書の id。トークンには / などが入りうるので、本物は中身の token に持つ。"""
    return hashlib.sha256(token.encode()).hexdigest()


def _push(tokens: list[str], type_: str, text: str) -> list[str]:
    """FCM で送り、もう使えないトークンを返す。"""
    import firebase_admin
    from firebase_admin import messaging

    if not firebase_admin._apps:
        firebase_admin.initialize_app()
    msg = messaging.MulticastMessage(tokens=tokens, notification=messaging.Notification(title="WEARBY", body=text),
                                     data={"type": type_})
    res = messaging.send_each_for_multicast(msg)
    for r in res.responses:
        if not r.success:  # 種類だけ (トークンはログに出さない)
            logging.warning("push failed: %s", type(r.exception).__name__)
    dead = (messaging.UnregisteredError, messaging.SenderIdMismatchError)
    return [t for t, r in zip(tokens, res.responses) if not r.success and isinstance(r.exception, dead)]


def notify(db, uid: str, type_: str, text: str, **ref) -> None:
    try:  # Firestore の一時の失敗も含め、通知が落ちても呼び出し元 (いいね・申請) は成功させる
        db.collection(f"users/{uid}/notifications").add(
            {"type": type_, "text": text, "createdAt": firestore.SERVER_TIMESTAMP, "read": False, **ref})
        tokens = [t for d in db.collection(f"users/{uid}/devices").stream() if (t := d.to_dict().get("token"))]
        for t in _push(tokens, type_, text) if tokens else []:
            db.document(f"users/{uid}/devices/{device_id(t)}").delete()
    except Exception as e:
        logging.warning("notify failed: %s", type(e).__name__)


def notify_once(db, key: str, uid: str, type_: str, text: str, **ref) -> None:
    """同じ key (種類・送った人・受けた人・対象) の通知は 1 日 1 回 (取り消して送り直すのを繰り返すと、プッシュを何度も送れるため)。"""
    day = datetime.now(timezone(timedelta(hours=9))).date().isoformat()
    try:
        db.document("notifyOnce/" + hashlib.sha256(f"{key}|{day}".encode()).hexdigest()).create({"at": firestore.SERVER_TIMESTAMP})
    except AlreadyExists:
        return
    except Exception as e:
        logging.warning("notify failed: %s", type(e).__name__)
        return
    notify(db, uid, type_, text, **ref)
