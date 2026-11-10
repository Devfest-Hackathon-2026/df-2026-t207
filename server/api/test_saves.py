"""服の保存 (saves.py)。服の情報だけを残し、画像と誰の服かは残さない。"""
from datetime import datetime, timedelta

import pytest
from fastapi.testclient import TestClient

from auth import User, current_user
from main import app
from nearby import GARMENT_KEYS
from routes_me import JST, today_jst

ITEM = {"slot": "outer", "category": "jacket", "label": "デニムジャケット", "color": "ライトブルー", "pattern": "無地",
        "image": "users/o1/jobs/j/item-0.png", "memo": "古着", "vector": [0.1], "createdAt": datetime.now(JST)}


def client(uid="v1", anon=False):
    app.dependency_overrides[current_user] = lambda: User(uid, anon)
    return TestClient(app)


@pytest.fixture(autouse=True)
def _cleanup():
    yield
    app.dependency_overrides.pop(current_user, None)


def seed(db, visibility="nearby", expires=None):
    db.document("users/o1/wardrobeItems/w1").set(ITEM)
    db.document(f"users/o1/dailyOutfits/{today_jst()}").set({
        "visibility": visibility, "image": "users/o1/jobs/j/outfit.png", "items": ["w1"],
        "snapshot": [{**{k: ITEM[k] for k in GARMENT_KEYS if k in ITEM}, "itemId": "w1", "memo": "古着",
                      "image": "/v1/jobs/j/images/item-0"}]})
    db.document("cards/c_1").set({"owner": "o1", "viewer": "v1", "outfitRef": f"users/o1/dailyOutfits/{today_jst()}",
                                  "items": {"a": "w1"}, "demo": False,
                                  "expiresAt": expires or datetime.now(JST) + timedelta(minutes=10)})
    db.document("friendships/f_1").set({"members": ["v1", "o1"], "since": datetime.now(JST)})


def stored(db, uid="v1"):
    return [d.to_dict() for d in db.collection(f"users/{uid}/saves").stream()]


GARMENT = {"slot": "outer", "category": "jacket", "label": "デニムジャケット", "color": "ライトブルー", "pattern": "無地"}


@pytest.mark.parametrize("body,source", [({"cardId": "c_1", "cardItemId": "a"}, "nearby"),
                                         ({"friendId": "f_1", "index": 0}, "friend")])
def test_save_keeps_only_garment_info(db, body, source):
    seed(db)
    r = client().post("/v1/saves", json=body)
    assert r.status_code == 201
    out = r.json()
    assert out["saveId"].startswith("s_") and out["source"] == source and "savedAt" in out
    assert {k: out[k] for k in GARMENT} == GARMENT
    [doc] = stored(db)
    assert set(doc) <= set(GARMENT_KEYS) | {"source", "savedAt"}  # 画像の path・持ち主・cardId・手持ちの id を残さない


def test_save_survives_card_expiry_and_lists_newest_first(db):
    seed(db)
    c = client()
    first = c.post("/v1/saves", json={"cardId": "c_1", "cardItemId": "a"}).json()["saveId"]
    second = c.post("/v1/saves", json={"friendId": "f_1", "index": 0}).json()["saveId"]
    db.document("cards/c_1").delete()
    items = c.get("/v1/saves").json()["items"]
    assert [i["saveId"] for i in items] == [second, first]
    assert c.delete(f"/v1/saves/{first}").status_code == 204
    assert [i["saveId"] for i in c.get("/v1/saves").json()["items"]] == [second]


def test_expired_card_is_410_and_missing_item_is_404(db):
    seed(db, expires=datetime.now(JST) - timedelta(seconds=1))
    assert client().post("/v1/saves", json={"cardId": "c_1", "cardItemId": "a"}).status_code == 410
    seed(db)
    assert client().post("/v1/saves", json={"cardId": "c_1", "cardItemId": "z"}).status_code == 404


@pytest.mark.parametrize("uid,index,visibility", [("v1", 5, "nearby"), ("v1", 0, "private"), ("v2", 0, "nearby")])
def test_friend_save_out_of_range_private_or_not_friend_is_404(db, uid, index, visibility):
    seed(db, visibility=visibility)
    assert client(uid).post("/v1/saves", json={"friendId": "f_1", "index": index}).status_code == 404
    assert stored(db, uid) == []


def test_anonymous_can_save_from_card_but_not_from_friend(db):
    seed(db)
    db.document("cards/c_1").update({"viewer": "anon1"})
    c = client("anon1", anon=True)
    assert c.post("/v1/saves", json={"cardId": "c_1", "cardItemId": "a"}).status_code == 201
    assert c.post("/v1/saves", json={"friendId": "f_1", "index": 0}).status_code == 403
    assert len(c.get("/v1/saves").json()["items"]) == 1


def test_bad_body_is_422_and_others_save_is_not_deleted(db):
    seed(db)
    assert client().post("/v1/saves", json={"cardId": "c_1"}).status_code == 422
    sid = client("v2").post("/v1/saves", json={"cardId": "c_1", "cardItemId": "a"})  # v2 のカードではない
    assert sid.status_code == 404
    mine = client().post("/v1/saves", json={"cardId": "c_1", "cardItemId": "a"}).json()["saveId"]
    assert client("v2").delete(f"/v1/saves/{mine}").status_code == 204
    assert len(stored(db)) == 1


def test_save_is_charged(db, monkeypatch):
    monkeypatch.setenv("QUOTA_SAVE", "1")
    seed(db)
    c = client()
    assert c.post("/v1/saves", json={"cardId": "c_1", "cardItemId": "a"}).status_code == 201
    assert c.post("/v1/saves", json={"cardId": "c_1", "cardItemId": "a"}).status_code == 429
