"""通知の一覧と既読、端末の登録、/v1/me に足す 2 つ (notifications.py)。"""
from datetime import datetime, timedelta

import pytest
from fastapi.testclient import TestClient

from auth import User, current_user
from main import app
from notify import device_id
from routes_me import JST, today_jst

T0 = datetime(2026, 11, 9, 12, 0, tzinfo=JST)


@pytest.fixture
def c(db):
    app.dependency_overrides[current_user] = lambda: User("u1", False)
    yield TestClient(app)
    app.dependency_overrides.pop(current_user, None)


def seed_notes(db, n=3, uid="u1"):
    for i in range(n):
        db.document(f"users/{uid}/notifications/n{i}").set(
            {"type": "like", "text": f"t{i}", "createdAt": T0 + timedelta(minutes=i), "read": False})


def test_put_device_stores_token_under_safe_id_and_delete_removes_it(c, db):
    tok = "abc:APA91b/xyz+=="  # FCM のトークンには / や : が入りうる
    assert c.put("/v1/me/devices", json={"token": tok}).status_code == 204
    doc = db.document(f"users/u1/devices/{device_id(tok)}").get()
    assert doc.to_dict()["token"] == tok
    assert c.request("DELETE", "/v1/me/devices", json={"token": tok}).status_code == 204
    assert not doc.reference.get().exists


def test_device_moves_to_the_last_account_that_registered_it(db):
    """同じ端末で別のアカウントに入り直したら、前のアカウントの通知はその端末に届けない。"""
    for uid in ("u1", "u2"):
        app.dependency_overrides[current_user] = lambda uid=uid: User(uid, False)
        assert TestClient(app).put("/v1/me/devices", json={"token": "tok"}).status_code == 204
    app.dependency_overrides.pop(current_user, None)
    assert not db.document(f"users/u1/devices/{device_id('tok')}").get().exists
    assert db.document(f"users/u2/devices/{device_id('tok')}").get().exists


def test_resent_friend_request_notifies_once(c, db, monkeypatch):
    import notify

    monkeypatch.setattr(notify, "_push", lambda *a: [])
    db.document("friendCodes/ABCDEFGH").set({"uid": "u2"})
    for _ in range(3):
        rid = c.post("/v1/friends/requests", json={"friendCode": "ABCDEFGH"}).json()["requestId"]
        assert c.delete(f"/v1/friends/requests/{rid}").status_code == 204
    assert len(list(db.collection("users/u2/notifications").stream())) == 1


def test_put_device_rejects_too_long_token(c):
    assert c.put("/v1/me/devices", json={"token": "x" * 4097}).status_code == 422


def test_anonymous_can_register_device(db):
    app.dependency_overrides[current_user] = lambda: User("anon1", True)
    try:
        assert TestClient(app).put("/v1/me/devices", json={"token": "t"}).status_code == 204
    finally:
        app.dependency_overrides.pop(current_user, None)
    assert db.document(f"users/anon1/devices/{device_id('t')}").get().exists


def test_list_is_newest_first_with_unread_count(c, db):
    seed_notes(db, 3)
    db.document("users/u1/notifications/n0").update({"read": True, "requestId": "r_1"})
    db.document("users/u2/notifications/x").set({"type": "like", "text": "他人", "createdAt": T0, "read": False})
    r = c.get("/v1/notifications").json()
    assert [i["id"] for i in r["items"]] == ["n2", "n1", "n0"]
    assert r["unread"] == 2
    last = r["items"][2]
    assert datetime.fromisoformat(last.pop("createdAt")) == T0
    assert last == {"id": "n0", "type": "like", "text": "t0", "read": True, "requestId": "r_1"}


def test_list_is_capped_at_50(c, db):
    seed_notes(db, 52)
    r = c.get("/v1/notifications").json()
    assert len(r["items"]) == 50 and r["items"][0]["id"] == "n51" and r["unread"] == 52


def test_read_marks_given_ids_and_ignores_unknown(c, db):
    seed_notes(db, 3)
    assert c.post("/v1/notifications/read", json={"ids": ["n1", "nope"]}).status_code == 204
    assert [d.id for d in db.collection("users/u1/notifications").stream() if d.get("read")] == ["n1"]
    assert not db.document("users/u1/notifications/nope").get().exists


def test_read_without_ids_marks_all(c, db):
    seed_notes(db, 3)
    assert c.post("/v1/notifications/read", json={}).status_code == 204
    assert c.get("/v1/notifications").json()["unread"] == 0


def test_me_fields_counts_todays_likes_and_unread(db):
    from notifications import me_fields

    assert me_fields(db, "u1") == {"likeCountToday": 0, "unreadNotifications": 0}
    seed_notes(db, 2)
    db.document(f"users/u1/dailyOutfits/{today_jst()}").set({"likeCount": 3})
    assert me_fields(db, "u1") == {"likeCountToday": 3, "unreadNotifications": 2}
