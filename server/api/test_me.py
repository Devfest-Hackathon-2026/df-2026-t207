import pytest
from fastapi.testclient import TestClient

from auth import User, current_user
from main import app


@pytest.fixture
def c(db):
    app.dependency_overrides[current_user] = lambda: User("u1", False)
    yield TestClient(app)
    app.dependency_overrides.clear()


def test_me_new_user_defaults(c):
    r = c.get("/v1/me")
    assert r.status_code == 200
    assert r.json() == {
        "uid": "u1",
        "displayName": "",
        "isAnonymous": False,
        "publishing": {"visibility": "private"},
        "viewCountToday": 0,
        "hasPhoto": False,
        "friendCode": r.json()["friendCode"],
        "profileImage": None,
        "profileCrop": None,
        "likeCountToday": 0,
        "unreadNotifications": 0,
    }
    assert len(r.json()["friendCode"]) == 8


def test_patch_me_sets_name(c):
    assert c.patch("/v1/me", json={"displayName": "りお"}).status_code == 200
    assert c.get("/v1/me").json()["displayName"] == "りお"


@pytest.mark.parametrize("name", ["", "あ" * 21])
def test_patch_me_rejects_empty_and_over_20(c, name):
    r = c.patch("/v1/me", json={"displayName": name})
    assert r.status_code == 422
    assert r.json()["error"]["code"] == "validation"


def test_without_token_error_matches_spec(db):
    r = TestClient(app).get("/v1/me")
    assert r.status_code == 401
    assert r.json()["error"]["code"] == "unauthenticated"


def test_anonymous_me_has_no_friend_code(c, db):
    """Web デモの匿名の利用者には、フレンドコードを作らない (匿名の uid ごとに増えないように)"""
    from auth import User, current_user
    from main import app

    app.dependency_overrides[current_user] = lambda: User("anon", True)
    body = c.get("/v1/me").json()
    assert "friendCode" not in body and body["unreadNotifications"] == 0
    assert not list(db.collection("friendCodes").stream())


def test_anonymous_me_is_the_publishing_demo_viewer(c, db, monkeypatch):
    """Web デモの審査員は、今日のコーデを公開しているデモの見る人として見える (名前・公開中・見られた数)。
    デモの人物の着姿は日付に依らず一番新しい物を使う (凍結の後もデータを足さずに見せるため)"""
    from auth import User, current_user
    from main import app

    monkeypatch.setenv("DEMO_VIEWER_UID", "demo_v")
    db.document("users/demo_v").set({"displayName": "Demo", "demo": True, "hasPhoto": True})
    db.document("users/demo_v/dailyOutfits/2026-11-09").set({"image": "x.png", "items": [], "viewCount": 3})
    app.dependency_overrides[current_user] = lambda: User("anon", True)
    body = c.get("/v1/me").json()
    assert body["displayName"] == "Demo" and body["isAnonymous"] is True
    assert body["publishing"]["visibility"] == "nearby" and body["publishing"]["until"]
    assert body["viewCountToday"] == 3 and body["hasPhoto"] is True


def test_anonymous_cannot_rename(c, db):
    """Web デモの審査員は名前を変えられない (匿名の uid ごとに文書が増え、しかも Demo のまま見える)"""
    from auth import User, current_user
    from main import app

    app.dependency_overrides[current_user] = lambda: User("anon", True)
    assert c.patch("/v1/me", json={"displayName": "X"}).status_code == 403
    assert not db.document("users/anon").get().exists


def test_demo_today_skips_latest_without_image(db):
    from routes_me import demo_today

    db.document("users/d/dailyOutfits/2026-11-09").set({"image": "a.png"})
    db.document("users/d/dailyOutfits/2026-11-10").set({"items": []})  # 画像の無い記録 (手で足した物など)
    assert demo_today(db, "d") == ("2026-11-09", {"image": "a.png"})
