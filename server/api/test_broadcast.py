import re
from datetime import datetime

import pytest
from fastapi.testclient import TestClient

from auth import User, current_user
from broadcast import issue_ids
from main import app
from routes_me import JST, today_jst


@pytest.fixture
def c(db):
    app.dependency_overrides[current_user] = lambda: User("u1", False)
    yield TestClient(app)
    app.dependency_overrides.clear()


def seed_outfit(db, uid="u1"):
    db.document(f"users/{uid}/dailyOutfits/{today_jst()}").set({"items": ["w_01"]})


def test_issue_ids_covers_until_midnight(db):
    ids = issue_ids(db, "u1", datetime(2026, 11, 8, 23, 52, tzinfo=JST))
    assert [i["slotStart"] for i in ids] == ["2026-11-08T23:50:00+09:00", "2026-11-08T23:55:00+09:00"]


def test_ids_are_22_hex_and_unique(db):
    ids = issue_ids(db, "u1", datetime(2026, 11, 8, 10, 0, tzinfo=JST))
    assert len(ids) == 14 * 12
    assert all(re.fullmatch(r"[0-9a-f]{22}", i["id"]) for i in ids)
    assert len({i["id"] for i in ids}) == len(ids)


def test_publish_without_today_outfit_is_409(c):
    r = c.put("/v1/publish", json={"visibility": "nearby"})
    assert r.status_code == 409
    assert r.json()["error"]["code"] == "no_outfit_today"


def test_publish_returns_ids_and_until_midnight(c, db):
    seed_outfit(db)
    r = c.put("/v1/publish", json={"visibility": "nearby"})
    body = r.json()
    assert body["visibility"] == "nearby"
    assert body["until"].endswith("T00:00:00+09:00")
    assert len(body["broadcastIds"]) >= 1
    assert c.get("/v1/me").json()["publishing"]["visibility"] == "nearby"


def test_republish_invalidates_old_ids(c, db):
    seed_outfit(db)
    old = c.put("/v1/publish", json={"visibility": "nearby"}).json()["broadcastIds"][0]["id"]
    c.put("/v1/publish", json={"visibility": "nearby"})
    assert not db.document(f"broadcastIds/{old}").get().exists


def test_private_returns_no_ids_and_removes_old(c, db):
    seed_outfit(db)
    old = c.put("/v1/publish", json={"visibility": "nearby"}).json()["broadcastIds"][0]["id"]
    body = c.put("/v1/publish", json={"visibility": "private"}).json()
    assert body == {"visibility": "private"}
    assert not db.document(f"broadcastIds/{old}").get().exists


def test_demo_owner_can_publish_without_today_outfit(c, db, monkeypatch):
    monkeypatch.setenv("DEMO_UIDS", "u1")
    db.document("users/u1/dailyOutfits/2026-11-01").set({"items": ["w_01"]})
    assert c.put("/v1/publish", json={"visibility": "nearby"}).status_code == 200


def test_publish_sets_generation_on_ids(c, db):
    seed_outfit(db)
    bid = c.put("/v1/publish", json={"visibility": "nearby"}).json()["broadcastIds"][0]["id"]
    assert db.document(f"broadcastIds/{bid}").get().get("gen") == db.document("users/u1").get().get("publishGen")
