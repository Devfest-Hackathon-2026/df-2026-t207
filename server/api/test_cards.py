from datetime import datetime, timedelta

import pytest
from fastapi import HTTPException

from auth import User, acting_uid
from cards import load_card
from routes_me import JST

NOW = datetime(2026, 11, 8, 12, 0, tzinfo=JST)


def seed_card(db, cid="c_1", viewer="v1", expires=NOW + timedelta(minutes=10)):
    db.document("users/o1/dailyOutfits/2026-11-08").set({"visibility": "nearby"})
    db.document(f"cards/{cid}").set({"owner": "o1", "viewer": viewer, "outfitRef": "users/o1/dailyOutfits/2026-11-08",
                                     "expiresAt": expires, "items": {"a": "w1"}})


def test_load_card_returns_doc(db):
    seed_card(db)
    assert load_card(db, "c_1", "v1", NOW)["items"] == {"a": "w1"}


@pytest.mark.parametrize("cid,viewer,status", [("c_x", "v1", 404), ("c_1", "v2", 404)])
def test_missing_or_other_viewers_card_is_404(db, cid, viewer, status):
    seed_card(db)
    with pytest.raises(HTTPException) as e:
        load_card(db, cid, viewer, NOW)
    assert e.value.status_code == status and e.value.detail["code"] == "not_found"


def test_expired_card_is_410(db):
    seed_card(db, expires=NOW - timedelta(seconds=1))
    with pytest.raises(HTTPException) as e:
        load_card(db, "c_1", "v1", NOW)
    assert e.value.status_code == 410 and e.value.detail["code"] == "card_expired"


def test_acting_uid_is_demo_viewer_for_anonymous(monkeypatch):
    monkeypatch.setenv("DEMO_VIEWER_UID", "demo_v")
    assert acting_uid(User("anon1", True)) == "demo_v"
    assert acting_uid(User("u1", False)) == "u1"


def test_acting_uid_without_demo_viewer_is_403(monkeypatch):
    monkeypatch.delenv("DEMO_VIEWER_UID", raising=False)
    with pytest.raises(HTTPException) as e:
        acting_uid(User("anon1", True))
    assert e.value.status_code == 403


# --- 口 ---
import io  # noqa: E402

from fastapi.testclient import TestClient  # noqa: E402
from PIL import Image  # noqa: E402

from auth import current_user  # noqa: E402
from main import app  # noqa: E402
from routes_me import today_jst  # noqa: E402


def rgba_png(w=200, h=300):
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    im.paste((200, 30, 30, 255), (50, 50, 150, 250))  # 人物の形の所だけ不透明
    buf = io.BytesIO()
    im.save(buf, "PNG")
    return buf.getvalue()


@pytest.fixture
def c(db, blobs):
    app.dependency_overrides[current_user] = lambda: User("v1", False)
    yield TestClient(app)
    app.dependency_overrides.pop(current_user, None)


def seed_live_card(db, blobs, cid="c_live1"):
    from datetime import datetime as dt

    db.document("users/o1/dailyOutfits/2026-11-08").set({"visibility": "nearby", "image": "users/o1/jobs/j/outfit.png", "items": ["w1"]})
    db.document("users/o1/wardrobeItems/w1").set({"slot": "top", "label": "ニット", "color": "赤", "image": "users/o1/jobs/j/item-0.png"})
    blobs.put("users/o1/jobs/j/outfit.png", rgba_png())
    blobs.put("users/o1/jobs/j/item-0.png", rgba_png(100, 100))
    db.document(f"cards/{cid}").set({"owner": "o1", "viewer": "v1", "outfitRef": "users/o1/dailyOutfits/2026-11-08",
                                     "expiresAt": dt.now(JST) + timedelta(minutes=10), "items": {"a": "w1"},
                                     "image": "users/o1/jobs/j/outfit.png", "demo": False})


def test_card_images_are_the_original_png(c, db, blobs):
    seed_live_card(db, blobs)
    for path, src in [("/v1/cards/c_live1/image", "users/o1/jobs/j/outfit.png"), ("/v1/cards/c_live1/items/a/image", "users/o1/jobs/j/item-0.png")]:
        r = c.get(path)
        assert r.status_code == 200 and r.headers["content-type"] == "image/png" and "no-store" in r.headers["cache-control"]
        assert r.content == blobs.get(src)  # 透かしは入れない (2026-11-08 チームの判断。画面の保存は Android で止めている)


def test_card_image_of_other_viewer_is_404(c, db, blobs):
    seed_live_card(db, blobs)
    app.dependency_overrides[current_user] = lambda: User("v2", False)
    assert c.get("/v1/cards/c_live1/image").status_code == 404
    assert c.get("/v1/cards/c_live1/items/z/image").status_code == 404


def test_block_hides_owner_from_nearby(c, db, blobs):
    seed_live_card(db, blobs)
    assert c.post("/v1/blocks", json={"cardId": "c_live1"}).status_code == 204
    assert db.document("blocks/v1_o1").get().exists


def test_report_is_recorded(c, db, blobs):
    seed_live_card(db, blobs)
    assert c.post("/v1/reports", json={"cardId": "c_live1", "reason": "not_clothes", "note": "x"}).status_code == 204
    rep = [d.to_dict() for d in db.collection("reports").stream()]
    assert rep[0]["owner"] == "o1" and rep[0]["reason"] == "not_clothes"
    assert c.post("/v1/reports", json={"cardId": "c_live1", "reason": "spam"}).status_code == 422


def test_demo_nearby_returns_demo_cards_to_anyone(c, db, blobs, monkeypatch):
    monkeypatch.setenv("DEMO_UIDS", "o1,o2")
    monkeypatch.setenv("WEB_DEMO_UIDS", "o1,o2")
    db.document("users/o1/dailyOutfits/2026-11-01").set({"image": "users/o1/jobs/j/outfit.png", "items": ["w1"]})
    db.document("users/o1/wardrobeItems/w1").set({"slot": "top", "label": "ニット", "color": "赤"})
    assert len(c.post("/v1/demo/nearby").json()["cards"]) == 1  # Google でログインした人も、実機無しで試せる (返るのは架空の人物だけ)
    app.dependency_overrides[current_user] = lambda: User("anon", True)
    body = c.post("/v1/demo/nearby").json()
    assert body["viewerPublishing"] is True
    assert len(body["cards"]) == 1 and body["cards"][0]["isDemo"] is True  # 着姿の無い o2 は出さない
    card = db.document(f"cards/{body['cards'][0]['cardId']}").get().to_dict()
    assert card["viewer"] == "anon" and card["owner"] == "o1"
    assert "o1" not in str(body) and "w1" not in str(body)


def test_admin_reset_needs_the_right_token(c, monkeypatch):
    monkeypatch.setenv("ADMIN_TOKEN", "s3cret")
    assert c.post("/v1/admin/demo/reset", headers={"X-Admin-Token": "nope"}).status_code == 401
    assert c.post("/v1/admin/demo/reset", headers={"X-Admin-Token": "s3cret"}).status_code == 204
    monkeypatch.delenv("ADMIN_TOKEN")
    assert c.post("/v1/admin/demo/reset", headers={"X-Admin-Token": ""}).status_code == 401


def test_bad_card_id_is_404_not_500(db):
    with pytest.raises(HTTPException) as e:
        load_card(db, "c_a/b", "v1", NOW)
    assert e.value.status_code == 404


def test_card_of_owner_who_stopped_publishing_is_410(c, db, blobs):
    seed_live_card(db, blobs)
    db.document("users/o1/dailyOutfits/2026-11-08").set({"visibility": "private"}, merge=True)
    assert c.get("/v1/cards/c_live1/image").status_code == 410


def test_card_keeps_the_outfit_image_it_was_made_with(c, db, blobs):
    from datetime import datetime as dt

    from nearby import make_card

    ref = db.document("users/o1/dailyOutfits/2026-11-08")
    ref.set({"visibility": "nearby", "image": "users/o1/jobs/old/outfit.png", "items": []})
    blobs.put("users/o1/jobs/old/outfit.png", rgba_png())
    blobs.put("users/o1/jobs/new/outfit.png", rgba_png(50, 50))
    card = make_card(db, "v1", "o1", ref, ref.get().to_dict(), dt.now(JST), dt.now(JST), False)
    ref.set({"image": "users/o1/jobs/new/outfit.png"}, merge=True)  # 登録し直した
    assert Image.open(io.BytesIO(c.get(card["image"]).content)).size == (200, 300)


def test_demo_nearby_skips_blocked_demo_person(c, db, blobs, monkeypatch):
    monkeypatch.setenv("WEB_DEMO_UIDS", "o1")
    db.document("users/o1/dailyOutfits/2026-11-01").set({"image": "users/o1/jobs/j/outfit.png", "items": []})
    db.document("blocks/anon_o1").set({})
    app.dependency_overrides[current_user] = lambda: User("anon", True)
    assert c.post("/v1/demo/nearby").json()["cards"] == []


def test_web_demo_shows_only_web_demo_people(c, db, blobs, monkeypatch):
    """壇上の本人 (stageA) は DEMO_UIDS に入れても、Web の審査員には出さない"""
    monkeypatch.setenv("DEMO_UIDS", "o1,stageA")
    monkeypatch.setenv("WEB_DEMO_UIDS", "o1")
    for uid in ("o1", "stageA"):
        db.document(f"users/{uid}/dailyOutfits/2026-11-01").set({"image": f"users/{uid}/jobs/j/outfit.png", "items": []})
    app.dependency_overrides[current_user] = lambda: User("anon", True)
    cards = c.post("/v1/demo/nearby").json()["cards"]
    assert [db.document(f"cards/{x['cardId']}").get().get("owner") for x in cards] == ["o1"]


def test_blocking_a_demo_card_keeps_the_demo_person(c, db, blobs):
    """デモの人物をブロックしても記録しない。審査員がその人を二度と見られなくなるのを防ぐ (2026-11-10 のレビュー)"""
    seed_live_card(db, blobs)
    db.document("cards/c_live1").set({"demo": True}, merge=True)
    assert c.post("/v1/blocks", json={"cardId": "c_live1"}).status_code == 204
    assert not list(db.collection("blocks").stream())
