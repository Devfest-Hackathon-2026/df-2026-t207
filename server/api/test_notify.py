"""通知を作る部品 (notify.notify)。Firestore に置き、登録した端末へプッシュする。"""
from notify import device_id, notify, notify_once


def test_notify_stores_doc_and_pushes_to_devices(db, monkeypatch):
    import notify as n

    sent = []
    monkeypatch.setattr(n, "_push", lambda tokens, type_, text: sent.append((sorted(tokens), type_, text)) or [])
    for t in ("tok-a", "tok-b"):
        db.document(f"users/u1/devices/{device_id(t)}").set({"token": t, "at": 1})
    notify(db, "u1", "friend_request", "さくらさんからフレンドの申請が届きました", requestId="r_1")
    docs = [d.to_dict() for d in db.collection("users/u1/notifications").stream()]
    assert len(docs) == 1 and docs[0]["type"] == "friend_request" and docs[0]["read"] is False and docs[0]["requestId"] == "r_1"
    assert sent == [(["tok-a", "tok-b"], "friend_request", "さくらさんからフレンドの申請が届きました")]


def test_notify_drops_dead_tokens_and_survives_push_errors(db, monkeypatch):
    import notify as n

    db.document(f"users/u1/devices/{device_id('dead')}").set({"token": "dead", "at": 1})
    monkeypatch.setattr(n, "_push", lambda tokens, type_, text: ["dead"])  # FCM が「もう無い」と返したトークン
    notify(db, "u1", "like", "近くの人からいいねが付きました")
    assert not db.document(f"users/u1/devices/{device_id('dead')}").get().exists
    monkeypatch.setattr(n, "_push", lambda *a: (_ for _ in ()).throw(RuntimeError("fcm down")))
    notify(db, "u1", "like", "x")  # プッシュが落ちても通知は残り、例外を外に出さない
    assert len(list(db.collection("users/u1/notifications").stream())) == 2


class BrokenDb:
    """Firestore が一時的に落ちている時の代わり。"""

    def __getattr__(self, name):
        raise RuntimeError("firestore unavailable")


def test_notify_and_notify_once_never_raise_on_firestore_errors():
    notify(BrokenDb(), "u1", "like", "x")
    notify_once(BrokenDb(), "k", "u1", "like", "x")


def test_notify_once_sends_once_per_key_a_day(db, monkeypatch):
    import notify as n

    monkeypatch.setattr(n, "_push", lambda *a: [])
    for _ in range(3):
        notify_once(db, "like|v1|o1", "o1", "like", "近くの人からいいねが付きました")
    notify_once(db, "like|v2|o1", "o1", "like", "近くの人からいいねが付きました")
    assert len(list(db.collection("users/o1/notifications").stream())) == 2
    assert all("v1" not in d.id for d in db.collection("notifyOnce").stream())  # 鍵は hash で、uid を素で残さない


def test_push_logs_why_each_failed_send_failed(monkeypatch, caplog):
    """宛先ごとの失敗 (権限が無い等) が黙って消えていた (11/9、端末にプッシュが届かない)。種類だけをログに出す (トークンは出さない)"""
    import firebase_admin
    from firebase_admin import messaging

    import notify as n

    class Res:
        def __init__(self, ok, exc=None):
            self.success, self.exception = ok, exc

    class Denied(Exception):
        pass

    monkeypatch.setattr(firebase_admin, "_apps", {"x": 1})
    monkeypatch.setattr(messaging, "send_each_for_multicast", lambda msg: type("B", (), {"responses": [Res(True), Res(False, Denied("tok-secret"))]})())
    with caplog.at_level("WARNING"):
        assert n._push(["tok-ok", "tok-secret"], "like", "x") == []
    assert "Denied" in caplog.text and "tok-secret" not in caplog.text
