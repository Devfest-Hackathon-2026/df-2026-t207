from datetime import datetime, timedelta

import pytest
from fastapi.testclient import TestClient

import ai
from auth import User, current_user
from main import app
from routes_me import JST

NOW = datetime.now(JST)


@pytest.fixture
def c(db, blobs, monkeypatch):
    monkeypatch.delenv("AI_DISABLED", raising=False)
    monkeypatch.setenv("DEMO_UIDS", "demo_o")
    monkeypatch.setenv("DEMO_VIEWER_UID", "demo_v")
    app.dependency_overrides[current_user] = lambda: User("v1", False)
    yield TestClient(app)
    app.dependency_overrides.pop(current_user, None)


def seed(db, blobs, *, owner="o1", viewer="v1", me="v1", expires=None):
    """owner のデニムジャケット (カードの a) と、me の手持ち 3 着 (上着・白T・パンツ) を置く。"""
    db.document(f"users/{owner}/wardrobeItems/w_seen").set({"slot": "outer", "label": "デニムジャケット", "color": "ライトブルー",
                                                            "image": f"users/{owner}/jobs/j1/item-0.png"})
    blobs.put(f"users/{owner}/jobs/j1/item-0.png", b"SEEN")
    for n, (wid, slot, label) in enumerate([("w_out", "outer", "コート"), ("w_t", "top", "白T"), ("w_p", "bottom", "パンツ")]):
        db.document(f"users/{me}/wardrobeItems/{wid}").set({"slot": slot, "label": label, "color": "白", "image": f"users/{me}/jobs/j2/item-{n}.png",
                                                            "createdAt": NOW - timedelta(minutes=n)})
        blobs.put(f"users/{me}/jobs/j2/item-{n}.png", wid.encode())
    db.document(f"users/{owner}/dailyOutfits/2026-11-08").set({"visibility": "nearby"})
    db.document("cards/c_1").set({"owner": owner, "viewer": viewer, "outfitRef": f"users/{owner}/dailyOutfits/2026-11-08",
                                  "expiresAt": expires or NOW + timedelta(minutes=10), "items": {"a": "w_seen"},
                                  "demo": owner == "demo_o"})


def fake_match(result):
    calls = []

    def f(seen, seen_png, candidates):
        calls.append((seen, seen_png, candidates))
        return result
    return f, calls


def quota(db, uid="v1"):
    return (db.document(f"quotas/{uid}_{NOW.date().isoformat()}").get().to_dict() or {}).get("match", 0)


def test_match_passes_all_owned_and_returns_result(c, db, blobs, monkeypatch):
    seed(db, blobs)
    f, calls = fake_match({"combos": [{"wardrobeItemIds": ["w_t", "w_p"], "reason": "合う"}], "missing": None, "similarOwned": None})
    monkeypatch.setattr(ai, "ask_match", f)
    r = c.post("/v1/match", json={"cardId": "c_1", "cardItemId": "a"})
    assert r.status_code == 200
    seen, png, cands = calls[0]
    assert seen["label"] == "デニムジャケット" and "image" not in seen and png == b"SEEN"
    assert [(i, b) for i, _, b in cands] == [("w_out", b"w_out"), ("w_t", b"w_t"), ("w_p", b"w_p")]  # 似た服を探すため同じ区分 (上着) も渡す
    body = r.json()
    assert body["seen"] == {"slot": "outer", "label": "デニムジャケット", "color": "ライトブルー", "cardItemId": "a",
                            "image": "/v1/cards/c_1/items/a/image"}
    assert body["combos"] == [{"wardrobeItemIds": ["w_t", "w_p"], "reason": "合う"}]
    assert body["missing"] is None and body["similarOwned"] is None
    assert quota(db) == 1


def test_unknown_ids_are_dropped(c, db, blobs, monkeypatch):
    seed(db, blobs)
    combos = [{"wardrobeItemIds": ["w_t", "w_zzz"], "reason": "x"}, {"wardrobeItemIds": ["w_p"], "reason": "y"},
              {"wardrobeItemIds": ["w_seen"], "reason": "z"}] + [{"wardrobeItemIds": ["w_t"], "reason": str(n)} for n in range(3)]
    f, _ = fake_match({"combos": combos, "missing": None, "similarOwned": {"wardrobeItemId": "w_other", "reason": "似ている"}})
    monkeypatch.setattr(ai, "ask_match", f)
    body = c.post("/v1/match", json={"cardId": "c_1", "cardItemId": "a"}).json()
    assert [x["reason"] for x in body["combos"]] == ["y", "0", "1"]
    assert body["similarOwned"] is None


@pytest.mark.parametrize("card,item,status", [("c_1", "z", 404), ("c_x", "a", 404)])
def test_unknown_card_or_item_is_404(c, db, blobs, card, item, status):
    seed(db, blobs)
    r = c.post("/v1/match", json={"cardId": card, "cardItemId": item})
    assert r.status_code == status and r.json()["error"]["code"] == "not_found"


def test_expired_card_is_410_without_charge(c, db, blobs):
    seed(db, blobs, expires=NOW - timedelta(seconds=1))
    r = c.post("/v1/match", json={"cardId": "c_1", "cardItemId": "a"})
    assert r.status_code == 410 and quota(db) == 0


def test_ai_disabled_without_precomputed_is_503(c, db, blobs, monkeypatch):
    seed(db, blobs)
    monkeypatch.setenv("AI_DISABLED", "1")
    r = c.post("/v1/match", json={"cardId": "c_1", "cardItemId": "a"})
    assert r.status_code == 503 and r.json()["error"]["code"] == "ai_disabled"
    assert quota(db) == 0


def test_ai_disabled_raised_by_ai_is_503(c, db, blobs, monkeypatch):
    seed(db, blobs)

    def off(*a):
        raise ai.AiDisabled()
    monkeypatch.setattr(ai, "ask_match", off)
    assert c.post("/v1/match", json={"cardId": "c_1", "cardItemId": "a"}).status_code == 503


PRE = {"combos": [{"wardrobeItemIds": ["w_t"], "reason": "事前"}], "missing": None, "similarOwned": None}


def anon(c):
    app.dependency_overrides[current_user] = lambda: User("anon1", True)


def test_demo_owner_is_matched_live_even_with_precomputed(c, db, blobs, monkeypatch):
    """デモの人物でも毎回その場で照合する。事前の結果を今作った物に見せない (2026-11-10 白井さん)"""
    anon(c)
    seed(db, blobs, owner="demo_o", viewer="anon1", me="demo_v")
    db.document("precomputed/match_demo_v_demo_o_w_seen").set(PRE)
    f, calls = fake_match({"combos": [], "missing": {"slot": "shoes", "description": "白のスニーカー"}, "similarOwned": None})
    monkeypatch.setattr(ai, "ask_match", f)
    body = c.post("/v1/match", json={"cardId": "c_1", "cardItemId": "a"}).json()
    assert calls and body["precomputed"] is False and body["missing"]["slot"] == "shoes"
    assert body["seen"]["cardItemId"] == "a"


def test_ai_disabled_uses_precomputed(c, db, blobs, monkeypatch):
    anon(c)
    seed(db, blobs, owner="o1", viewer="anon1", me="demo_v")
    db.document("precomputed/match_demo_v_o1_w_seen").set(PRE)
    monkeypatch.setenv("AI_DISABLED", "1")
    assert c.post("/v1/match", json={"cardId": "c_1", "cardItemId": "a"}).json()["precomputed"] is True


def test_precomputed_is_not_given_to_other_viewers(c, db, blobs, monkeypatch):
    """事前の結果はデモの見る人の手持ちで作る物。ほかの人には返さない (他人の手持ちの id を返さない)。"""
    seed(db, blobs, owner="demo_o")
    db.document("precomputed/match_demo_v_demo_o_w_seen").set(PRE)
    f, calls = fake_match({"combos": [], "missing": {"slot": "shoes", "description": "白のスニーカー"}, "similarOwned": None})
    monkeypatch.setattr(ai, "ask_match", f)
    body = c.post("/v1/match", json={"cardId": "c_1", "cardItemId": "a"}).json()
    assert calls and body["precomputed"] is False and body["missing"]["slot"] == "shoes"


def test_anonymous_without_demo_viewer_is_403(c, db, blobs, monkeypatch):
    anon(c)
    monkeypatch.delenv("DEMO_VIEWER_UID")
    seed(db, blobs, viewer="anon1")
    r = c.post("/v1/match", json={"cardId": "c_1", "cardItemId": "a"})
    assert r.status_code == 403 and quota(db, "anon1") == 0


def test_ai_disabled_env_stops_ask_match(monkeypatch):
    monkeypatch.setenv("AI_DISABLED", "1")
    with pytest.raises(ai.AiDisabled):
        ai.ask_match({}, b"", [])
    with pytest.raises(ai.AiDisabled):
        ai.make_tryon(b"", [])


def test_anonymous_calls_share_one_quota(c, db, blobs, monkeypatch):
    monkeypatch.setattr(ai, "ask_match", fake_match({"combos": [], "missing": None, "similarOwned": None})[0])
    for uid in ("anon1", "anon2"):  # 匿名でログインし直しても、別の上限にならない
        app.dependency_overrides[current_user] = lambda uid=uid: User(uid, True)
        seed(db, blobs, owner="o1", viewer=uid, me="demo_v")
        assert c.post("/v1/match", json={"cardId": "c_1", "cardItemId": "a"}).status_code == 200
    assert quota(db, "anonymous") == 2 and quota(db, "anon-each-anon1") == 1  # 全員の枠と、1 人ごとの枠の両方を数える


def test_one_anonymous_user_cannot_use_up_everyones_quota(c, db, blobs, monkeypatch):
    """匿名の 1 人ごとにも上限を置く。1 人が使い切っても、ほかの審査員は止まらない (2026-11-10 白井さん、照合 50・着用イメージ 40)"""
    monkeypatch.setattr(ai, "ask_match", fake_match({"combos": [], "missing": None, "similarOwned": None})[0])
    monkeypatch.setenv("QUOTA_ANON_EACH_MATCH", "1")
    for uid, want in (("anon1", 200), ("anon1", 429), ("anon2", 200)):
        app.dependency_overrides[current_user] = lambda uid=uid: User(uid, True)
        seed(db, blobs, owner="o1", viewer=uid, me="demo_v")
        assert c.post("/v1/match", json={"cardId": "c_1", "cardItemId": "a"}).status_code == want
    assert quota(db, "anonymous") == 2  # 断った 1 回は全員の枠を減らさない


def test_ai_failure_is_502_in_error_shape(c, db, blobs, monkeypatch):
    seed(db, blobs)
    monkeypatch.setattr(ai, "ask_match", lambda *a: (_ for _ in ()).throw(ValueError("blocked")))
    r = c.post("/v1/match", json={"cardId": "c_1", "cardItemId": "a"})
    assert r.status_code == 502 and r.json()["error"]["code"] == "internal"


def test_same_slot_item_is_kept_out_of_combos_but_can_be_similar(c, db, blobs, monkeypatch):
    seed(db, blobs)
    out = {"combos": [{"wardrobeItemIds": ["w_out", "w_t"], "reason": "上着を 2 枚"}, {"wardrobeItemIds": ["w_t", "w_p"], "reason": "合う"}],
           "missing": None, "similarOwned": {"wardrobeItemId": "w_out", "reason": "形と色が近い"}}
    monkeypatch.setattr(ai, "ask_match", fake_match(out)[0])
    body = c.post("/v1/match", json={"cardId": "c_1", "cardItemId": "a"}).json()
    assert [x["reason"] for x in body["combos"]] == ["合う"]  # 見た上着と一緒に、手持ちの上着は着ない
    assert body["similarOwned"] == {"wardrobeItemId": "w_out", "reason": "形と色が近い"}


def test_combo_over_3_items_is_dropped(c, db, blobs, monkeypatch):
    """着用イメージは手持ち 3 着まで (/v1/tryon の wardrobeItemIds)。照合の組み合わせもそれに合わせる"""
    seed(db, blobs)
    db.document("users/v1/wardrobeItems/w_s").set({"slot": "shoes", "label": "靴", "image": "users/v1/jobs/j2/item-0.png"})
    db.document("users/v1/wardrobeItems/w_b").set({"slot": "bag", "label": "かばん", "image": "users/v1/jobs/j2/item-1.png"})
    out = {"combos": [{"wardrobeItemIds": ["w_t", "w_p", "w_s", "w_b"], "reason": "4 着"}, {"wardrobeItemIds": ["w_t", "w_p", "w_s"], "reason": "3 着"}],
           "missing": None, "similarOwned": None}
    monkeypatch.setattr(ai, "ask_match", fake_match(out)[0])
    body = c.post("/v1/match", json={"cardId": "c_1", "cardItemId": "a"}).json()
    assert [x["reason"] for x in body["combos"]] == ["3 着"]


def test_call_ai_retries_when_gemini_is_unavailable(monkeypatch):
    """Gemini の 503 (一時的に使えない) も、429 と同じく待ってやり直す (レビュー A4)"""
    import match

    monkeypatch.setattr(match.time, "sleep", lambda s: None)
    calls = []

    def flaky():
        calls.append(1)
        if len(calls) == 1:
            raise RuntimeError("503 UNAVAILABLE")
        return "ok"

    assert match.call_ai(flaky) == "ok" and len(calls) == 2
