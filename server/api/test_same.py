"""同じ服の判定 (GET /v1/jobs/{jobId}/same-items と、PUT /v1/outfits/today の sameAs、tasks の L1)。"""
from datetime import datetime

import pytest
from fastapi.testclient import TestClient

import ai
from auth import User, current_user
from main import app
from routes_me import JST, today_jst

JOB = "job_abcdef12"
NOW = datetime.now(JST)
RESULT = {"outfitImage": "x", "items": [
    {"index": 0, "slot": "top", "label": "白T", "color": "白", "image": "x", "points": []},
    {"index": 1, "slot": "shoes", "label": "スニーカー", "color": "白", "image": "x", "points": []},
]}


@pytest.fixture
def c(db, blobs, monkeypatch):
    monkeypatch.delenv("AI_DISABLED", raising=False)
    app.dependency_overrides[current_user] = lambda: User("u1", False)
    db.document(f"users/u1/jobs/{JOB}").set({"status": "succeeded", "result": RESULT})
    for n in (0, 1):
        blobs.put(f"users/u1/jobs/{JOB}/item-{n}.png", f"NEW{n}".encode())
    # 手持ち: 白T に近い物 2 着と遠い物 1 着 (上着は区分が違う)
    for wid, slot, vec in [("w_near", "top", [1, 0, 0]), ("w_mid", "top", [0.7, 0.7, 0]), ("w_far", "top", [0, 0, 1]),
                           ("w_coat", "outer", [1, 0, 0]), ("w_novec", "top", None)]:
        doc = {"slot": slot, "label": wid, "image": f"users/u1/jobs/old/{wid}.png", "createdAt": NOW}
        if vec:
            doc["vector"] = vec
        db.document(f"users/u1/wardrobeItems/{wid}").set(doc)
        blobs.put(f"users/u1/jobs/old/{wid}.png", wid.encode())
    monkeypatch.setattr(ai, "embed", lambda png: [1, 0, 0] if png == b"NEW0" else [0, 1, 0])
    yield TestClient(app)
    app.dependency_overrides.pop(current_user, None)


def fake_pick(answer):
    calls = []

    def pick(item, png, candidates):
        calls.append((item["label"], png, [c[0] for c in candidates]))
        return answer(item, candidates)
    return pick, calls


def test_same_items_asks_gemini_with_nearest_same_slot_items(c, monkeypatch):
    pick, calls = fake_pick(lambda item, cands: {"wardrobeItemId": "w_near", "reason": "形と色が同じ"} if item["label"] == "白T" else None)
    monkeypatch.setattr(ai, "pick_same", pick)
    r = c.get(f"/v1/jobs/{JOB}/same-items")
    assert r.status_code == 200
    assert ("白T", b"NEW0", ["w_near", "w_mid", "w_far"]) in calls  # 同じ区分で、ベクトルの近い順。上着とベクトルの無い物は入れない
    assert all(label != "スニーカー" for label, _, _ in calls)  # 同じ区分の手持ちが無い服は Gemini に聞かない
    items = r.json()["items"]
    assert [(i["index"], i["wardrobeItem"]["itemId"], i["reason"]) for i in items] == [(0, "w_near", "形と色が同じ")]
    assert "vector" not in items[0]["wardrobeItem"]


def test_gemini_answer_outside_candidates_is_dropped(c, monkeypatch):
    monkeypatch.setattr(ai, "pick_same", fake_pick(lambda item, cands: {"wardrobeItemId": "w_coat", "reason": "x"})[0])
    assert c.get(f"/v1/jobs/{JOB}/same-items").json()["items"] == []


def test_unfinished_job_is_409_and_unknown_is_404(c, db):
    db.document(f"users/u1/jobs/{JOB}").set({"status": "cutting"})
    assert c.get(f"/v1/jobs/{JOB}/same-items").json()["error"]["code"] == "not_ready"
    assert c.get("/v1/jobs/job_zzzzzzzz/same-items").status_code == 404


def test_anonymous_cannot_use_same_items(c):
    app.dependency_overrides[current_user] = lambda: User("anon", True)
    assert c.get(f"/v1/jobs/{JOB}/same-items").status_code == 403


def test_register_with_same_as_reuses_wardrobe_item(c, db):
    r = c.put("/v1/outfits/today", json={"jobId": JOB, "items": [{"index": 0, "sameAs": "w_near"}, {"index": 1}]})
    assert r.status_code == 200
    ids = db.document(f"users/u1/dailyOutfits/{today_jst()}").get().get("items")
    assert ids[0] == "w_near" and ids[1] != "w_near"
    assert len(list(db.collection("users/u1/wardrobeItems").stream())) == 6  # 新しく増えたのはスニーカーの 1 着だけ


def test_register_with_same_as_of_other_slot_or_unknown_is_400(c):
    for bad in ("w_coat", "w_nope"):
        r = c.put("/v1/outfits/today", json={"jobId": JOB, "items": [{"index": 0, "sameAs": bad}]})
        assert r.status_code == 400 and r.json()["error"]["code"] == "validation"


def test_register_stores_vector_for_new_items(c, db):
    body = c.put("/v1/outfits/today", json={"jobId": JOB, "items": [{"index": 1}]}).json()
    assert db.document(f"users/u1/wardrobeItems/{body['items'][0]['itemId']}").get().get("vector") == [0, 1, 0]


def test_register_still_works_when_embedding_fails(c, db, monkeypatch):
    monkeypatch.setattr(ai, "embed", lambda png: (_ for _ in ()).throw(RuntimeError("429")))
    assert c.put("/v1/outfits/today", json={"jobId": JOB, "items": [{"index": 1}]}).status_code == 200
