import io
from datetime import datetime, timedelta

import pytest
from fastapi.testclient import TestClient
from PIL import Image

import ai
from auth import User, current_user
from main import app
from routes_me import JST
from test_match import NOW, seed


def jpeg(size=(40, 80)):
    buf = io.BytesIO()
    Image.new("RGB", size, "white").save(buf, "JPEG")
    return buf.getvalue()


@pytest.fixture
def c(db, blobs, monkeypatch):
    monkeypatch.delenv("AI_DISABLED", raising=False)
    monkeypatch.setenv("DEMO_UIDS", "demo_o")
    monkeypatch.setenv("DEMO_VIEWER_UID", "demo_v")
    app.dependency_overrides[current_user] = lambda: User("v1", False)
    yield TestClient(app)
    app.dependency_overrides.pop(current_user, None)


def as_user(uid, anonymous=False):
    app.dependency_overrides[current_user] = lambda: User(uid, anonymous)


def put_photo(c, captured="camera", data=None):
    return c.put("/v1/me/photo", files={"photo": ("p.jpg", data or jpeg(), "image/jpeg")}, data={"capturedWith": captured})


def quota(db, uid="v1"):
    return (db.document(f"quotas/{uid}_{NOW.date().isoformat()}").get().to_dict() or {}).get("tryon", 0)


# --- 自分の写真 ---

def test_put_photo_stores_and_sets_has_photo(c, db, blobs):
    r = put_photo(c)
    assert r.status_code == 204
    assert blobs.get("users/v1/photo.jpg")
    assert db.document("users/v1").get().to_dict()["hasPhoto"] is True


@pytest.mark.parametrize("captured", ["gallery", ""])
def test_put_photo_not_from_camera_is_400(c, blobs, captured):
    r = put_photo(c, captured)
    assert r.status_code in (400, 422) and r.json()["error"]["code"] == "validation"
    assert not blobs.d


def test_put_photo_rejects_non_image(c, blobs):
    assert put_photo(c, data=b"not an image").status_code == 400 and not blobs.d


def test_put_photo_rejects_over_10mb(c, blobs):
    assert put_photo(c, data=jpeg() + bytes(10 * 2**20)).status_code == 400 and not blobs.d


def test_put_photo_shrinks_and_drops_exif(c, blobs):
    im, buf = Image.new("RGB", (1500, 3000), "white"), io.BytesIO()
    exif = Image.Exif()
    exif[0x010F] = "PhoneMaker"  # 端末の名前 (位置も同じ EXIF に入る)
    im.save(buf, "JPEG", exif=exif)
    assert put_photo(c, data=buf.getvalue()).status_code == 204
    out = Image.open(io.BytesIO(blobs.get("users/v1/photo.jpg")))
    assert out.format == "JPEG" and max(out.size) == 2048 and not out.getexif()


def test_anonymous_photo_goes_to_short_lived_place(c, db, blobs):
    """Web の審査員の写真は anon/ の下に置く (バケットの決まりで 1〜2 日で消える)。ユーザーの文書は作らない"""
    as_user("anon1", True)
    assert put_photo(c).status_code == 204
    assert blobs.get("anon/anon1/photo.jpg") and not blobs.get("users/anon1/photo.jpg")
    assert not db.document("users/anon1").get().exists
    assert c.delete("/v1/me/photo").status_code == 204
    assert blobs.get("anon/anon1/photo.jpg") is None


def test_delete_photo(c, db, blobs):
    put_photo(c)
    assert c.delete("/v1/me/photo").status_code == 204
    assert blobs.get("users/v1/photo.jpg") is None
    assert db.document("users/v1").get().to_dict()["hasPhoto"] is False


# --- 着用イメージ ---

def body(**kw):
    return {"cardId": "c_1", "cardItemId": "a", "wardrobeItemIds": ["w_t"], **kw}


def fake_tryon(monkeypatch):
    calls = []

    def f(photo, garments):
        calls.append((photo, garments))
        return b"PNG"
    monkeypatch.setattr(ai, "make_tryon", f)
    return calls


def test_tryon_without_photo_is_409(c, db, blobs, monkeypatch):
    seed(db, blobs)
    fake_tryon(monkeypatch)
    r = c.post("/v1/tryon", json=body())
    assert r.status_code == 409 and r.json()["error"]["code"] == "photo_required"
    assert quota(db) == 0


def test_tryon_makes_image_for_self_only(c, db, blobs, monkeypatch):
    seed(db, blobs)
    blobs.put("users/v1/photo.jpg", b"ME")
    calls = fake_tryon(monkeypatch)
    r = c.post("/v1/tryon", json=body(wardrobeItemIds=["w_t", "w_p"]))
    assert r.status_code == 200
    assert calls == [(b"ME", [b"SEEN", b"w_t", b"w_p"])]
    t = r.json()
    assert t["tryonId"].startswith("t_") and t["image"] == f"/v1/tryon/{t['tryonId']}/image"
    assert t["label"] == "AI による着用イメージ" and t["precomputed"] is False
    assert datetime.fromisoformat(t["generatedAt"]).tzinfo is not None
    assert blobs.get(f"users/v1/tryons/{t['tryonId']}.png") == b"PNG"
    assert db.document(f"users/v1/tryons/{t['tryonId']}").get().exists
    assert quota(db) == 1

    img = c.get(t["image"])
    assert img.status_code == 200 and img.content == b"PNG" and img.headers["content-type"] == "image/png"
    as_user("v2")
    assert c.get(t["image"]).status_code == 404


def test_tryon_image_unknown_id_is_404(c):
    assert c.get("/v1/tryon/t_nope/image").status_code == 404
    assert c.get("/v1/tryon/.../image").status_code == 404  # Firestore に渡せない id も 404 (500 にしない)


def test_tryon_rejects_more_than_3_items(c, db, blobs, monkeypatch):
    seed(db, blobs)
    blobs.put("users/v1/photo.jpg", b"ME")
    fake_tryon(monkeypatch)
    assert c.post("/v1/tryon", json=body(wardrobeItemIds=["w_t", "w_p", "w_out", "w_t"])).status_code == 422


def test_tryon_with_others_item_is_404(c, db, blobs, monkeypatch):
    seed(db, blobs)
    blobs.put("users/v1/photo.jpg", b"ME")
    fake_tryon(monkeypatch)
    r = c.post("/v1/tryon", json=body(wardrobeItemIds=["w_seen"]))  # 見た人の服の id は自分の手持ちに無い
    assert r.status_code == 404 and quota(db) == 0


def test_tryon_expired_card_is_410(c, db, blobs, monkeypatch):
    seed(db, blobs, expires=NOW - timedelta(seconds=1))
    blobs.put("users/v1/photo.jpg", b"ME")
    assert c.post("/v1/tryon", json=body()).status_code == 410


def seed_demo(db, blobs):
    as_user("anon1", True)
    seed(db, blobs, owner="demo_o", viewer="anon1", me="demo_v")
    blobs.put("precomputed/tryon_demo_o.png", b"PRE")
    db.document("precomputed/tryon_demo_v_demo_o_w_seen_w_t").set({"image": "precomputed/tryon_demo_o.png"})  # 見た服 + 選んだ手持ちごと


def test_demo_owner_is_generated_live_even_with_precomputed(c, db, blobs, monkeypatch):
    """デモの人物でも最初からその場で生成する。事前の画像を今作った物に見せない (2026-11-10 白井さん)"""
    seed_demo(db, blobs)
    blobs.put("users/demo_v/photo.jpg", b"DEMO_ME")
    calls = fake_tryon(monkeypatch)
    t = c.post("/v1/tryon", json=body()).json()
    assert t["precomputed"] is False and calls[0][0] == b"DEMO_ME"
    assert blobs.get(f"anon/anon1/tryons/{t['tryonId']}.png") == b"PNG"  # 結果は本人 (匿名の uid) の物で、1〜2 日で消える置き場


def test_ai_disabled_returns_precomputed_and_503_without_it(c, db, blobs, monkeypatch):
    seed_demo(db, blobs)
    monkeypatch.setenv("AI_DISABLED", "1")
    assert c.post("/v1/tryon", json=body()).json()["precomputed"] is True
    as_user("v1")
    seed(db, blobs)
    blobs.put("users/v1/photo.jpg", b"ME")
    r = c.post("/v1/tryon", json=body())
    assert r.status_code == 503 and r.json()["error"]["code"] == "ai_disabled"


def test_ai_label_is_burned_into_tryon_image():
    import io

    from PIL import Image

    import ai

    buf = io.BytesIO()
    Image.new("RGB", (400, 600), (90, 120, 160)).save(buf, "PNG")
    out = Image.open(io.BytesIO(ai.label_ai(buf.getvalue()))).convert("RGB")
    assert out.size == (400, 600)
    assert out.crop((0, 540, 400, 600)).getcolors(10000) != [(400 * 60, (90, 120, 160))]  # 下の帯に文字が入る
    assert out.getpixel((200, 100)) == (90, 120, 160)  # 上は元のまま


def test_precomputed_tryon_is_per_chosen_items(c, db, blobs, monkeypatch):
    seed_demo(db, blobs)
    blobs.put("users/demo_v/photo.jpg", b"DEMO_ME")
    calls = fake_tryon(monkeypatch)
    t = c.post("/v1/tryon", json=body(wardrobeItemIds=["w_p"])).json()  # 事前に作っていない組み合わせ
    assert t["precomputed"] is False and len(calls) == 1


def test_bad_wardrobe_id_is_404_not_500(c, db, blobs, monkeypatch):
    seed(db, blobs)
    blobs.put("users/v1/photo.jpg", b"ME")
    fake_tryon(monkeypatch)
    assert c.post("/v1/tryon", json=body(wardrobeItemIds=["__x__"])).status_code == 404


def test_tryon_ai_failure_is_502(c, db, blobs, monkeypatch):
    seed(db, blobs)
    blobs.put("users/v1/photo.jpg", b"ME")
    monkeypatch.setattr(ai, "make_tryon", lambda *a: (_ for _ in ()).throw(IndexError()))
    r = c.post("/v1/tryon", json=body())
    assert r.status_code == 502 and r.json()["error"]["code"] == "internal"


def test_anonymous_with_own_photo_uses_it_not_precomputed(c, db, blobs, monkeypatch):
    seed_demo(db, blobs)
    blobs.put("users/demo_v/photo.jpg", b"DEMO_ME")
    blobs.put("anon/anon1/photo.jpg", b"JUDGE")
    calls = fake_tryon(monkeypatch)
    t = c.post("/v1/tryon", json=body()).json()
    assert t["precomputed"] is False and calls[0][0] == b"JUDGE"  # 手持ちはデモの見る人の物、写真は本人の物
    assert quota(db, "anonymous") == 1


def test_tryon_retries_when_ai_is_busy(c, db, blobs, monkeypatch):
    """画像の生成はすぐ 429 になる (試験で 1 本ずつでも 24 回)。少し待ってやり直す"""
    import match

    seed(db, blobs)
    blobs.put("users/v1/photo.jpg", b"ME")
    monkeypatch.setattr(match, "BUSY_WAITS", (0, 0))
    tries = []

    def busy_once(photo, garments):
        tries.append(1)
        if len(tries) == 1:
            raise RuntimeError("429 RESOURCE_EXHAUSTED")
        return b"PNG"
    monkeypatch.setattr(ai, "make_tryon", busy_once)
    r = c.post("/v1/tryon", json=body())
    assert r.status_code == 200 and len(tries) == 2


def test_make_tryon_falls_back_to_second_model_when_first_is_busy(monkeypatch):
    """画像の生成はモデルごとに 1 分 2 回まで (調整できない上限)。1 つ目が 429 なら 2 つ目のモデルで作る"""
    import io

    from PIL import Image

    png = io.BytesIO()
    Image.new("RGB", (40, 80), "white").save(png, "PNG")
    tried = []

    class Part:
        def __init__(self, data):
            self.inline_data = type("D", (), {"data": data})()

    class Models:
        def generate_content(self, model, contents, config):
            tried.append(model)
            if model == ai.TRYON_MODELS[0]:
                raise RuntimeError("429 RESOURCE_EXHAUSTED")
            return type("R", (), {"candidates": [type("C", (), {"content": type("X", (), {"parts": [Part(png.getvalue())]})()})()]})()

    monkeypatch.setattr(ai, "_client", lambda: type("Cl", (), {"models": Models()})())
    monkeypatch.delenv("AI_DISABLED", raising=False)
    out = ai.make_tryon(b"", [png.getvalue()])
    assert tried == list(ai.TRYON_MODELS) and out.startswith(b"\x89PNG")


def test_put_photo_rejects_huge_pixel_count(c, blobs):
    buf = io.BytesIO()
    Image.new("L", (6400, 6400)).save(buf, "JPEG")  # ファイルは小さいが、展開すると 4,096 万画素
    assert put_photo(c, data=buf.getvalue()).status_code == 400 and not blobs.d
