"""seed_demo (D2) と precompute_demo (D3) の試験。Firestore はエミュレータ (127.0.0.1:8181)、Storage と AI は偽物。

流し方 (scripts で): <venv>/python -m pytest -q test_demo.py
"""
import io
import os
import sys
import urllib.request
from datetime import datetime

import pytest
from PIL import Image

os.environ.setdefault("FIRESTORE_EMULATOR_HOST", "127.0.0.1:8181")
PROJECT = "demo-df-hack26-scripts"
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "server", "api"))

from precompute_demo import precompute  # noqa: E402
from routes_me import JST  # noqa: E402
from seed_demo import seed  # noqa: E402

NOW = datetime(2026, 11, 9, 10, 0, tzinfo=JST)


class Blobs(dict):
    def get(self, path):
        return dict.get(self, path)

    def put(self, path, data, content_type="image/png"):
        self[path] = data

    def delete(self, path):
        self.pop(path, None)


@pytest.fixture
def db():
    from google.cloud import firestore

    host = os.environ["FIRESTORE_EMULATOR_HOST"]
    urllib.request.urlopen(urllib.request.Request(
        f"http://{host}/emulator/v1/projects/{PROJECT}/databases/(default)/documents", method="DELETE")).close()
    return firestore.Client(project=PROJECT)


def jpeg(path, color="white"):
    Image.new("RGB", (60, 120), color).save(path, "JPEG")


@pytest.fixture
def folder(tmp_path):
    (tmp_path / "viewer").mkdir()
    (tmp_path / "people").mkdir()
    jpeg(tmp_path / "viewer" / "photo.jpg")
    jpeg(tmp_path / "viewer" / "outfit-1.jpg")
    jpeg(tmp_path / "viewer" / "outfit-2.jpg")
    jpeg(tmp_path / "people" / "Aki.jpg")
    jpeg(tmp_path / "people" / "Ren.jpg")
    return tmp_path


def fake_vision(img):
    """どの写真からも上着と白 T の 2 着が出る、とする"""
    return {"outfitImage": b"OUTFIT", "items": [
        {"index": 0, "slot": "outer", "label": "ジャケット", "color": "カーキ", "image": b"ITEM0", "points": []},
        {"index": 1, "slot": "top", "label": "白T", "color": "白", "image": b"ITEM1", "points": []},
    ]}


def test_seed_writes_people_and_viewer_and_returns_env(db, folder):
    blobs = Blobs()
    env = seed(db, blobs, folder, "demo", fake_vision, NOW)
    assert env == {"DEMO_UIDS": "demo-aki,demo-ren", "WEB_DEMO_UIDS": "demo-aki,demo-ren", "DEMO_VIEWER_UID": "demo-viewer"}
    day = db.document("users/demo-aki/dailyOutfits/2026-11-09").get().to_dict()
    assert len(day["items"]) == 2 and blobs.get(day["image"]) == b"OUTFIT"
    assert [x["label"] for x in day["snapshot"]] == ["ジャケット", "白T"]  # 投稿時点の写し (アプリのカレンダーとフレンドの投稿が読む)
    assert day["outfitImage"].startswith("/v1/jobs/seed_") and day["snapshot"][0]["image"].endswith("/images/item-0")
    w = db.document(f"users/demo-aki/wardrobeItems/{day['items'][0]}").get().to_dict()
    assert w["label"] == "ジャケット" and blobs.get(w["image"]) == b"ITEM0" and w["createdAt"]
    viewer = list(db.collection("users/demo-viewer/wardrobeItems").stream())
    assert len(viewer) == 4  # 着姿 2 枚 × 2 着
    assert db.document("users/demo-viewer").get().get("hasPhoto") is True
    photo = Image.open(io.BytesIO(blobs.get("users/demo-viewer/photo.jpg")))
    assert photo.format == "JPEG"


def test_seed_again_replaces_old_data(db, folder):
    blobs = Blobs()
    seed(db, blobs, folder, "demo", fake_vision, NOW)
    seed(db, blobs, folder, "demo", fake_vision, NOW)
    assert len(list(db.collection("users/demo-viewer/wardrobeItems").stream())) == 4
    assert len([p for p in blobs if p.startswith("users/demo-aki/")]) == 3  # 前の分は消える


def test_precompute_writes_match_and_tryon_per_combo(db, folder):
    blobs = Blobs()
    seed(db, blobs, folder, "demo", fake_vision, NOW)
    viewer_items = sorted(d.id for d in db.collection("users/demo-viewer/wardrobeItems").stream())
    asked, made = [], []

    def ask(seen, seen_png, candidates):
        asked.append(seen["label"])
        other = [wid for wid, g, _ in candidates if g["slot"] != seen["slot"]][0]  # 見た服と違う区分の 1 着
        return {"combos": [{"wardrobeItemIds": [other], "reason": "合う"}], "missing": None, "similarOwned": None}

    def make(photo, garments):
        made.append(len(garments))
        return b"TRYON"

    n = precompute(db, blobs, "demo-viewer", ["demo-aki"], ask, make)
    assert asked == ["ジャケット", "白T"] and n == {"match": 2, "tryon": 2}
    aki_items = db.document("users/demo-aki/dailyOutfits/2026-11-09").get().get("items")
    m = db.document(f"precomputed/match_demo-viewer_demo-aki_{aki_items[0]}").get().to_dict()
    assert m["combos"][0]["reason"] == "合う" and m["combos"][0]["wardrobeItemIds"][0] in viewer_items
    tid = m["combos"][0]["wardrobeItemIds"][0]
    t = db.document(f"precomputed/tryon_demo-viewer_demo-aki_{aki_items[0]}_{tid}").get().to_dict()
    assert blobs.get(t["image"]) == b"TRYON" and made == [2, 2]


def test_photo_stopped_by_vision_is_skipped(db, folder):
    def vision(img):
        if img[0, 0, 0] < 128:  # 黒い写真は「顔が残った」とする
            raise RuntimeError("face_detected")
        return fake_vision(img)

    jpeg(folder / "people" / "Ren.jpg", "black")
    env = seed(db, Blobs(), folder, "demo", vision, NOW)
    assert env["DEMO_UIDS"] == "demo-aki"  # 止まった人は入れない
