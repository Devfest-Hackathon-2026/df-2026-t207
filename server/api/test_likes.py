"""いいね (likes.py): 近くのカードとフレンドの今日の公開コーデ。"""
from datetime import datetime, timedelta

import pytest
from fastapi.testclient import TestClient

import notify
from auth import User, current_user
from main import app
from routes_me import JST, today_jst

DAY = today_jst()
OUTFIT = f"users/o1/dailyOutfits/{DAY}"


@pytest.fixture
def sent(monkeypatch):
    out = []
    monkeypatch.setattr(notify, "_push", lambda tokens, type_, text: out.append(text) or [])
    return out


def client(uid="v1", anon=False):
    app.dependency_overrides[current_user] = lambda: User(uid, anon)
    return TestClient(app)


@pytest.fixture(autouse=True)
def _cleanup():
    yield
    app.dependency_overrides.pop(current_user, None)


def seed(db, visibility="nearby", expires=None):
    db.document("users/o1").set({"displayName": "おーなー"})
    db.document("users/v1").set({"displayName": "さくら"})
    db.document("users/o1/devices/d").set({"token": "tok"})
    db.document(OUTFIT).set({"visibility": visibility, "image": "users/o1/jobs/j/outfit.png", "likeCount": 0})
    db.document("cards/c_1").set({"owner": "o1", "viewer": "v1", "outfitRef": OUTFIT, "items": {},
                                  "expiresAt": expires or datetime.now(JST) + timedelta(minutes=10), "demo": False})
    db.document("friendships/f_1").set({"members": ["v1", "o1"], "since": datetime.now(JST)})


def count(db):
    return db.document(OUTFIT).get().to_dict()["likeCount"]


def notes(db):
    return [d.to_dict() for d in db.collection("users/o1/notifications").stream()]


def test_card_like_counts_once_and_notifies_without_who(db, sent):
    seed(db)
    c = client()
    assert c.put("/v1/likes/cards/c_1").status_code == 204
    assert c.put("/v1/likes/cards/c_1").status_code == 204  # もう一度送っても 1 つ
    assert count(db) == 1
    assert [(n["type"], n["text"]) for n in notes(db)] == [("like", "近くの人からいいねが付きました")]
    assert sent == ["近くの人からいいねが付きました"]
    assert set(notes(db)[0]) == {"type", "text", "createdAt", "read"}  # カードも見た人も残さない


def test_card_unlike_decrements_and_repeat_is_noop(db, sent):
    seed(db)
    c = client()
    c.put("/v1/likes/cards/c_1")
    assert c.delete("/v1/likes/cards/c_1").status_code == 204
    assert c.delete("/v1/likes/cards/c_1").status_code == 204
    assert count(db) == 0


def test_like_record_is_not_under_owner(db, sent):
    """持ち主はアプリで users/{自分}/ の下を読めるので、誰がいいねしたかはそこに置かない。"""
    seed(db)
    client().put("/v1/likes/cards/c_1")
    assert len(list(db.collection("likes").stream())) == 1
    assert [c.id for c in db.document(OUTFIT).collections()] == []


def test_expired_card_like_is_410(db, sent):
    seed(db, expires=datetime.now(JST) - timedelta(seconds=1))
    assert client().put("/v1/likes/cards/c_1").status_code == 410
    assert count(db) == 0


def test_other_viewers_card_is_404(db, sent):
    seed(db)
    assert client("v2").put("/v1/likes/cards/c_1").status_code == 404


def test_friend_like_notifies_with_name_and_liked_flag(db, sent):
    import likes

    seed(db)
    c = client()
    assert c.put("/v1/likes/friends/f_1").status_code == 204
    assert c.put("/v1/likes/friends/f_1").status_code == 204
    assert count(db) == 1 and likes.liked(db, "v1", "o1", DAY) and not likes.liked(db, "v2", "o1", DAY)
    assert [n["text"] for n in notes(db)] == ["さくらさんからいいねが付きました"]
    assert c.delete("/v1/likes/friends/f_1").status_code == 204
    assert count(db) == 0 and not likes.liked(db, "v1", "o1", DAY)


def test_card_like_does_not_show_as_friend_liked(db, sent):
    """カードのいいねで FriendPost.liked が立つと、すれ違いの相手がどのフレンドか分かってしまう。"""
    import likes

    seed(db)
    c = client()
    c.put("/v1/likes/cards/c_1")
    assert not likes.liked(db, "v1", "o1", DAY)
    c.put("/v1/likes/friends/f_1")
    assert likes.liked(db, "v1", "o1", DAY) and count(db) == 2  # 数は両方を数える
    c.delete("/v1/likes/friends/f_1")
    assert not likes.liked(db, "v1", "o1", DAY) and count(db) == 1


@pytest.mark.parametrize("path", ["/v1/likes/cards/c_1", "/v1/likes/friends/f_1"])
def test_like_unlike_like_notifies_once_a_day(db, sent, path):
    seed(db)
    c = client()
    for _ in range(3):
        c.put(path)
        c.delete(path)
    c.put(path)
    assert count(db) == 1 and len(notes(db)) == 1 and len(sent) == 1


def test_friend_like_private_outfit_or_not_friend_is_404(db, sent):
    seed(db, visibility="private")
    assert client().put("/v1/likes/friends/f_1").status_code == 404
    assert client("v2").put("/v1/likes/friends/f_1").status_code == 404


def test_anonymous_can_like_card_but_not_friend(db, sent):
    seed(db)
    db.document("cards/c_1").update({"viewer": "anon1"})
    c = client("anon1", anon=True)
    assert c.put("/v1/likes/cards/c_1").status_code == 204
    assert c.put("/v1/likes/friends/f_1").status_code == 403


def test_like_is_charged(db, sent, monkeypatch):
    monkeypatch.setenv("QUOTA_LIKE", "1")
    seed(db)
    c = client()
    assert c.put("/v1/likes/cards/c_1").status_code == 204
    assert c.put("/v1/likes/cards/c_1").status_code == 429
