from datetime import datetime

import pytest
from fastapi.testclient import TestClient

from auth import User, current_user
from main import app
from routes_me import JST, today_jst

JOB = "job_abcdef12"
RESULT = {"outfitImage": f"/v1/jobs/{JOB}/images/outfit", "items": [
    {"index": 0, "slot": "outer", "category": "jacket", "label": "ジャケット", "layer": "outer", "color": "紺",
     "image": f"/v1/jobs/{JOB}/images/item-0", "points": [{"y": 300, "x": 350}]},
    {"index": 1, "slot": "bottom", "category": "pants", "label": "デニム", "layer": "single", "color": "青",
     "image": f"/v1/jobs/{JOB}/images/item-1", "points": [{"y": 700, "x": 500}]},
]}


@pytest.fixture
def c(db, blobs):
    app.dependency_overrides[current_user] = lambda: User("u1", False)
    yield TestClient(app)
    app.dependency_overrides.pop(current_user, None)


def seed_job(db, status="succeeded", **extra):
    db.document(f"users/u1/jobs/{JOB}").set({"status": status, "progress": 1, **({"result": RESULT} if status == "succeeded" else {}), **extra})


def register(c, items=({"index": 0, "memo": "古着"}, {"index": 1})):
    return c.put("/v1/outfits/today", json={"jobId": JOB, "items": list(items)})


def test_register_adds_wardrobe_and_today(c, db):
    seed_job(db)
    r = register(c)
    assert r.status_code == 200
    body = r.json()
    assert body["date"] == today_jst() and body["image"] == "/v1/outfits/today/image"
    assert [i["label"] for i in body["items"]] == ["ジャケット", "デニム"]
    first = body["items"][0]
    assert first["memo"] == "古着" and first["image"] == f"/v1/wardrobe/{first['itemId']}/image"
    assert "points" not in first and "index" not in first
    w = db.document(f"users/u1/wardrobeItems/{first['itemId']}").get().to_dict()
    assert w["image"] == f"users/u1/jobs/{JOB}/item-0.png"
    d = db.document(f"users/u1/dailyOutfits/{today_jst()}").get().to_dict()
    assert d["items"] == [i["itemId"] for i in body["items"]] and d["image"] == f"users/u1/jobs/{JOB}/outfit.png"


def test_register_only_selected_items(c, db):
    seed_job(db)
    assert [i["label"] for i in register(c, [{"index": 1}]).json()["items"]] == ["デニム"]


def test_register_keeps_publishing_state(c, db):
    seed_job(db)
    db.document(f"users/u1/dailyOutfits/{today_jst()}").set({"visibility": "nearby", "viewCount": 3})
    register(c)
    d = db.document(f"users/u1/dailyOutfits/{today_jst()}").get().to_dict()
    assert d["visibility"] == "nearby" and d["viewCount"] == 3


@pytest.mark.parametrize("status,extra,code", [("cutting", {}, "not_ready"),
                                               ("failed", {"error": {"code": "face_detected", "message": "x"}}, "face_detected")])
def test_unfinished_or_face_job_is_409(c, db, status, extra, code):
    seed_job(db, status, **extra)
    r = register(c)
    assert r.status_code == 409 and r.json()["error"]["code"] == code


def test_unknown_job_is_404(c):
    assert register(c).status_code == 404


def test_unknown_index_is_400(c, db):
    seed_job(db)
    r = register(c, [{"index": 5}])
    assert r.status_code == 400 and r.json()["error"]["code"] == "validation"


def test_anonymous_cannot_register(c, db):
    app.dependency_overrides[current_user] = lambda: User("anon", True)
    seed_job(db)
    assert register(c).status_code == 403


def test_get_today_404_then_200(c, db):
    assert c.get("/v1/outfits/today").status_code == 404
    seed_job(db)
    register(c)
    assert len(c.get("/v1/outfits/today").json()["items"]) == 2


def test_images_are_served_from_own_storage(c, db, blobs):
    seed_job(db)
    blobs.put(f"users/u1/jobs/{JOB}/outfit.png", b"\x89PNG-o")
    blobs.put(f"users/u1/jobs/{JOB}/item-0.png", b"\x89PNG-0")
    item = register(c, [{"index": 0}]).json()["items"][0]
    assert c.get(f"/v1/jobs/{JOB}/images/item-0").content == b"\x89PNG-0"
    assert c.get("/v1/outfits/today/image").content == b"\x89PNG-o"
    r = c.get(f"/v1/wardrobe/{item['itemId']}/image")
    assert r.content == b"\x89PNG-0" and r.headers["content-type"] == "image/png"
    assert "no-store" in r.headers["cache-control"]


@pytest.mark.parametrize("path", [f"/v1/jobs/{JOB}/images/secret", f"/v1/jobs/{JOB}/images/item-9", "/v1/jobs/x/images/outfit",
                                  "/v1/wardrobe/nope/image"])
def test_bad_or_missing_image_is_404(c, path):
    assert c.get(path).status_code == 404


def test_wardrobe_list_filter_and_delete(c, db):
    seed_job(db)
    items = register(c).json()["items"]
    assert len(c.get("/v1/wardrobe").json()["items"]) == 2
    assert [i["label"] for i in c.get("/v1/wardrobe?slot=bottom").json()["items"]] == ["デニム"]
    assert c.delete(f"/v1/wardrobe/{items[0]['itemId']}").status_code == 204
    assert [i["label"] for i in c.get("/v1/wardrobe").json()["items"]] == ["デニム"]


def test_anonymous_reads_demo_viewers_wardrobe(c, db, monkeypatch):
    seed_job(db)
    register(c)
    monkeypatch.setenv("DEMO_VIEWER_UID", "u1")
    app.dependency_overrides[current_user] = lambda: User("anon", True)
    assert len(c.get("/v1/wardrobe").json()["items"]) == 2
    assert c.delete("/v1/wardrobe/whatever").status_code == 403



def test_register_twice_with_same_job_returns_first_result(c, db):
    """通信が切れて送り直しても、手持ちが重複しない"""
    seed_job(db)
    first = register(c).json()
    again = register(c, [{"index": 1}])
    assert again.status_code == 200 and again.json() == first
    assert len(list(db.collection("users/u1/wardrobeItems").stream())) == 2


def test_register_keeps_snapshot_of_items_in_daily(c, db):
    """手持ちから消しても、その日のコーデの服を投稿時点のまま見られる"""
    seed_job(db)
    body = register(c).json()
    c.delete(f"/v1/wardrobe/{body['items'][0]['itemId']}")
    d = db.document(f"users/u1/dailyOutfits/{today_jst()}").get().to_dict()
    assert d["outfitImage"] == f"/v1/jobs/{JOB}/images/outfit"
    snap = d["snapshot"]
    assert [(s["label"], s["memo"], s["image"]) for s in snap] == [
        ("ジャケット", "古着", f"/v1/jobs/{JOB}/images/item-0"), ("デニム", "", f"/v1/jobs/{JOB}/images/item-1")]
    assert snap[0]["itemId"] == body["items"][0]["itemId"]


def seed_closet(db):
    db.document("users/u1/wardrobeItems/w_old").set({"slot": "shoes", "label": "白スニーカー", "color": "白", "memo": "手持ちのメモ",
                                                     "image": "users/u1/jobs/job_old0001/item-3.png", "createdAt": datetime.now(JST)})


def test_register_with_closet_item_and_note(c, db):
    """検出した服に、手持ちの服とメモだけの服を足して登録する"""
    seed_job(db)
    seed_closet(db)
    r = c.put("/v1/outfits/today", json={"jobId": JOB, "items": [
        {"index": 0}, {"wardrobeItemId": "w_old", "memo": "今日は紐を替えた"}, {"memo": "黒の靴下"}]})
    assert r.status_code == 200
    body = r.json()
    assert [i["label"] for i in body["items"]] == ["ジャケット", "白スニーカー"]
    assert body["items"][1]["memo"] == "今日は紐を替えた"  # コーデ専用のメモ
    assert body["itemNotes"] == ["黒の靴下"] and body["jobId"] == JOB
    assert db.document("users/u1/wardrobeItems/w_old").get().get("memo") == "手持ちのメモ"  # 手持ちのメモは変えない
    d = db.document(f"users/u1/dailyOutfits/{today_jst()}").get().to_dict()
    assert d["snapshot"][1]["image"] == "/v1/jobs/job_old0001/images/item-3" and d["itemNotes"] == ["黒の靴下"]
    assert len(list(db.collection("users/u1/wardrobeItems").stream())) == 2  # 新しく作ったのはジャケットだけ


@pytest.mark.parametrize("item", [{"wardrobeItemId": "w_nope"}, {"memo": "   "}, {"index": 0, "wardrobeItemId": "w_old"}, {}])
def test_register_rejects_bad_item_shapes(c, db, item):
    seed_job(db)
    seed_closet(db)
    r = c.put("/v1/outfits/today", json={"jobId": JOB, "items": [item]})
    assert r.status_code in (400, 422) and r.json()["error"]["code"] == "validation"


def test_edit_today_replaces_items_and_notes(c, db):
    """登録済みの今日のコーデを、同じ jobId と editDate で直す (服を外す・手持ちとメモを足す)"""
    seed_job(db)
    seed_closet(db)
    items = register(c).json()["items"]
    r = c.put("/v1/outfits/today", json={"jobId": JOB, "editDate": today_jst(), "items": [
        {"wardrobeItemId": items[1]["itemId"]}, {"wardrobeItemId": "w_old"}, {"memo": "ベルト"}]})
    assert r.status_code == 200
    assert [i["label"] for i in r.json()["items"]] == ["デニム", "白スニーカー"] and r.json()["itemNotes"] == ["ベルト"]
    assert len(list(db.collection("users/u1/wardrobeItems").stream())) == 3  # 編集では手持ちは増えない


def test_edit_with_detected_index_is_400(c, db):
    seed_job(db)
    register(c)
    r = c.put("/v1/outfits/today", json={"jobId": JOB, "editDate": today_jst(), "items": [{"index": 0}]})
    assert r.status_code == 400


@pytest.mark.parametrize("edit", [{"editDate": "2026-01-01"}, {"jobId": "job_zzzzzzzz"}])
def test_edit_of_other_day_or_other_job_is_409(c, db, edit):
    seed_job(db)
    register(c)
    if "jobId" in edit:
        db.document("users/u1/jobs/job_zzzzzzzz").set({"status": "succeeded", "result": RESULT})
    r = c.put("/v1/outfits/today", json={"jobId": JOB, "editDate": today_jst(), "items": []} | edit)
    assert r.status_code == 409


def test_anonymous_today_is_demo_viewers_latest_outfit(c, db, blobs, monkeypatch):
    """Web デモの審査員の「今日のコーデ」は、デモの見る人の一番新しいコーデ (日付に依らない)"""
    monkeypatch.setenv("DEMO_VIEWER_UID", "demo_v")
    db.document("users/demo_v/dailyOutfits/2026-11-01").set({"image": "users/demo_v/jobs/j/old.png", "items": []})
    db.document("users/demo_v/dailyOutfits/2026-11-09").set({"image": "users/demo_v/jobs/j/outfit.png", "items": []})
    blobs.put("users/demo_v/jobs/j/outfit.png", b"PNG")
    app.dependency_overrides[current_user] = lambda: User("anon", True)
    assert c.get("/v1/outfits/today").json()["date"] == "2026-11-09"
    assert c.get("/v1/outfits/today/image").content == b"PNG"
