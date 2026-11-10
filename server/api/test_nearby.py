import json
from datetime import datetime, timedelta

import pytest

from nearby import resolve
from routes_me import JST

NOW = datetime(2026, 11, 8, 10, 7, tzinfo=JST)
DAY = "2026-11-08"
SECRET = b"test-secret"


def seed_owner(db, uid, bid, *, day=DAY, visibility="nearby", slot_start=None, outer="デニムジャケット"):
    """uid が day に公開した着姿と手持ち 2 着、匿名 ID bid を置く"""
    db.document(f"users/{uid}/wardrobeItems/w_{uid}_1").set({"slot": "outer", "label": outer, "color": "ライトブルー"})
    db.document(f"users/{uid}/wardrobeItems/w_{uid}_2").set({"slot": "bottom", "label": "ロングスカート", "color": "レッド"})
    db.document(f"users/{uid}/dailyOutfits/{day}").set({"visibility": visibility, "items": [f"w_{uid}_1", f"w_{uid}_2"]})
    s = slot_start or NOW.replace(minute=5, second=0)
    db.document(f"users/{uid}").set({"publishGen": "g1"}, merge=True)
    db.document(f"broadcastIds/{bid}").set({"uid": uid, "date": day, "gen": "g1", "slotStart": s, "slotEnd": s + timedelta(minutes=5)})


def viewer_publishes(db, uid="viewer"):
    db.document(f"users/{uid}/dailyOutfits/{DAY}").set({"visibility": "nearby", "items": []})


def see(*bids, rssi=-60):
    return [{"id": b, "lastSeenAt": NOW.isoformat(), "rssi": rssi} for b in bids]


def run(db, sightings, *, viewer="viewer", now=NOW, demo=()):
    return resolve(db, viewer, sightings, now, set(demo), SECRET)


def test_returns_card_for_published_owner(db):
    viewer_publishes(db)
    seed_owner(db, "alice", "a" * 22)
    out = run(db, see("a" * 22))
    assert out["viewerPublishing"] is True
    assert len(out["cards"]) == 1
    labels = [i["label"] for i in out["cards"][0]["items"]]
    assert labels == ["デニムジャケット", "ロングスカート"]


def test_viewer_not_publishing_gets_empty(db):
    seed_owner(db, "alice", "a" * 22)
    assert run(db, see("a" * 22)) == {"cards": [], "viewerPublishing": False}


def test_same_owner_twice_today_is_hidden(db):
    viewer_publishes(db)
    seed_owner(db, "alice", "a" * 22)
    assert len(run(db, see("a" * 22))["cards"]) == 1
    assert run(db, see("a" * 22))["cards"] == []


def test_two_ids_of_same_owner_make_one_card(db):
    viewer_publishes(db)
    seed_owner(db, "alice", "a" * 22)
    seed_owner(db, "alice", "b" * 22, slot_start=NOW.replace(minute=0, second=0))
    assert len(run(db, see("a" * 22, "b" * 22))["cards"]) == 1


def test_own_id_is_ignored(db):
    viewer_publishes(db)
    seed_owner(db, "viewer", "v" * 22)
    assert run(db, see("v" * 22))["cards"] == []


def test_id_older_than_20min_after_slot_is_ignored(db):
    viewer_publishes(db)
    seed_owner(db, "alice", "a" * 22)  # 枠は 10:05〜10:10
    assert run(db, see("a" * 22), now=NOW.replace(minute=30, second=1))["cards"] == []


def test_id_exactly_20min_after_slot_is_accepted(db):
    viewer_publishes(db)
    seed_owner(db, "alice", "a" * 22)
    assert len(run(db, see("a" * 22), now=NOW.replace(minute=30, second=0))["cards"]) == 1


def test_unpublished_owner_is_hidden(db):
    viewer_publishes(db)
    seed_owner(db, "alice", "a" * 22, visibility="private")
    assert run(db, see("a" * 22))["cards"] == []


def test_blocked_owner_is_hidden(db):
    viewer_publishes(db)
    seed_owner(db, "alice", "a" * 22)
    db.document("blocks/viewer_alice").set({"at": NOW})
    assert run(db, see("a" * 22))["cards"] == []


def test_demo_owner_ignores_once_per_day_and_date(db):
    viewer_publishes(db)
    seed_owner(db, "demo1", "d" * 22, day="2026-11-01")  # 着姿は前の日に登録
    db.document("users/demo1/dailyOutfits/2026-11-01").update({"image": "users/demo1/jobs/j/outfit.png"})  # 本番のデモの記録は画像を持つ
    db.document(f"broadcastIds/{'d' * 22}").update({"date": DAY})
    first = run(db, see("d" * 22), demo=["demo1"])
    second = run(db, see("d" * 22), demo=["demo1"])
    assert len(first["cards"]) == 1 and len(second["cards"]) == 1
    assert first["cards"][0]["isDemo"] is True


def test_card_has_no_uid_or_item_ids(db):
    viewer_publishes(db)
    seed_owner(db, "alice", "a" * 22)
    text = json.dumps(run(db, see("a" * 22)))
    assert "alice" not in text
    assert "a" * 22 not in text
    assert "w_alice" not in text


def test_cards_sorted_newest_then_strongest(db):
    viewer_publishes(db)
    seed_owner(db, "alice", "a" * 22, outer="コート")
    seed_owner(db, "bob", "b" * 22, outer="ベスト")
    seed_owner(db, "carol", "c" * 22, outer="パーカー")
    sightings = see("a" * 22, rssi=-80) + see("b" * 22, rssi=-55)
    sightings += [{"id": "c" * 22, "lastSeenAt": (NOW + timedelta(seconds=30)).isoformat(), "rssi": -90}]
    out = run(db, sightings, now=NOW + timedelta(minutes=1))
    assert [c["items"][0]["label"] for c in out["cards"]] == ["パーカー", "ベスト", "コート"]


@pytest.mark.parametrize("bad", ["zz", "a" * 21])
def test_malformed_ids_are_ignored(db, bad):
    viewer_publishes(db)
    assert run(db, see(bad))["cards"] == []


def test_route_charges_and_resolves(db, monkeypatch):
    from fastapi.testclient import TestClient

    from auth import User, current_user
    from main import app

    monkeypatch.setenv("VIEWLOG_SECRET", "s")
    monkeypatch.setenv("QUOTA_NEARBY", "1")
    app.dependency_overrides[current_user] = lambda: User("viewer", False)
    try:
        c = TestClient(app)
        assert c.post("/v1/nearby", json={"sightings": []}).json() == {"cards": [], "viewerPublishing": False}
        assert c.post("/v1/nearby", json={"sightings": []}).status_code == 429
    finally:
        app.dependency_overrides.clear()


def test_viewer_outfit_without_visibility_is_not_publishing(db):
    db.document(f"users/viewer/dailyOutfits/{DAY}").set({"items": []})  # 登録しただけで公開していない
    seed_owner(db, "alice", "a" * 22)
    assert run(db, see("a" * 22)) == {"cards": [], "viewerPublishing": False}


def test_owner_outfit_without_visibility_is_hidden(db):
    viewer_publishes(db)
    seed_owner(db, "alice", "a" * 22)
    db.document(f"users/alice/dailyOutfits/{DAY}").set({"items": ["w_alice_1"]})
    assert run(db, see("a" * 22))["cards"] == []


def test_demo_viewer_still_once_per_day_for_real_owner(db):
    viewer_publishes(db, "demoV")
    seed_owner(db, "alice", "a" * 22)
    assert len(run(db, see("a" * 22), viewer="demoV", demo=["demoV"])["cards"]) == 1
    assert run(db, see("a" * 22), viewer="demoV", demo=["demoV"])["cards"] == []


def test_stale_publish_generation_is_ignored(db):
    viewer_publishes(db)
    seed_owner(db, "alice", "a" * 22)
    db.document("users/alice").set({"publishGen": "g2"}, merge=True)  # 後から公開し直した
    assert run(db, see("a" * 22))["cards"] == []


def _client(db, monkeypatch, user):
    from fastapi.testclient import TestClient

    from auth import current_user
    from main import app

    monkeypatch.setenv("VIEWLOG_SECRET", "s")
    app.dependency_overrides[current_user] = lambda: user
    return TestClient(app)


def test_anonymous_user_cannot_use_nearby_or_publish(db, monkeypatch):
    from auth import User
    from main import app

    c = _client(db, monkeypatch, User("anon1", True))
    try:
        assert c.post("/v1/nearby", json={"sightings": []}).status_code == 403
        assert c.put("/v1/publish", json={"visibility": "nearby"}).status_code == 403
    finally:
        app.dependency_overrides.clear()


@pytest.mark.parametrize(
    "bad",
    [{"id": "a" * 22, "lastSeenAt": "2026-11-08T10:07:00"}, {"id": 123, "lastSeenAt": NOW.isoformat()}, {"id": "a" * 22}],
)
def test_malformed_sighting_is_422_and_not_charged(db, monkeypatch, bad):
    from auth import User
    from main import app

    c = _client(db, monkeypatch, User("viewer", False))
    try:
        r = c.post("/v1/nearby", json={"sightings": [bad]})
        assert r.status_code == 422
        assert not db.collection("quotas").limit(1).get()
    finally:
        app.dependency_overrides.clear()


def test_owner_who_blocked_viewer_is_hidden(db):
    viewer_publishes(db)
    seed_owner(db, "alice", "a" * 22)
    db.document("blocks/alice_viewer").set({})  # 見られる側が見る人をブロックした
    assert run(db, see("a" * 22))["cards"] == []


def test_deleted_wardrobe_item_is_left_out_of_card(db):
    viewer_publishes(db)
    seed_owner(db, "alice", "a" * 22)
    db.document("users/alice/wardrobeItems/w_alice_1").delete()
    assert [i["label"] for i in run(db, see("a" * 22))["cards"][0]["items"]] == ["ロングスカート"]


def test_rssi_missing_does_not_break_choosing_the_strongest(db):
    """rssi が無い報告と有る報告が同じ時刻に重なっても 500 にしない (2026-11-10 のレビュー A6)"""
    viewer_publishes(db)
    seed_owner(db, "alice", "a" * 22)
    seed_owner(db, "alice", "b" * 22, slot_start=NOW.replace(minute=0, second=0))
    sightings = [{"id": "a" * 22, "lastSeenAt": NOW.isoformat(), "rssi": None},
                 {"id": "b" * 22, "lastSeenAt": NOW.isoformat(), "rssi": -60}]
    assert len(run(db, sightings)["cards"]) == 1


def test_demo_person_uses_latest_outfit_with_image(db):
    """デモの人物に画像の無い新しい記録があっても、画像の有る一番新しい記録で出す (レビュー A3)"""
    from nearby import _outfit

    db.document("users/demo/dailyOutfits/2026-11-09").set({"image": "a.png", "items": []})
    db.document("users/demo/dailyOutfits/2026-11-10").set({"items": []})
    ref, outfit = _outfit(db, "demo", None, True)
    assert ref.id == "2026-11-09" and outfit["image"] == "a.png"


def test_exempt_owner_is_seen_again_without_ai_badge(db, monkeypatch):
    """壇上の A (本物の人) は 1 日 1 回から外せる。デモの人物ではないので「AI 生成」の印は付けない (2026-11-10)"""
    monkeypatch.setenv("ONCE_A_DAY_EXEMPT_UIDS", "stage_a")
    viewer_publishes(db)
    seed_owner(db, "stage_a", "a" * 22)
    first = run(db, see("a" * 22))
    second = run(db, see("a" * 22))
    assert len(first["cards"]) == 1 and len(second["cards"]) == 1
    assert first["cards"][0]["isDemo"] is False
