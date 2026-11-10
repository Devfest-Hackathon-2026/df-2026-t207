import io
import os
import urllib.request
import uuid
from datetime import date

import numpy as np
import pytest
from google.api_core.exceptions import AlreadyExists
from fastapi.testclient import TestClient
from PIL import Image

import main
from pipeline import ProcessError

c = TestClient(main.app)  # with を付けないので startup (モデルの読み込み) は走らない
AUTH = {"Authorization": "Bearer tok"}
JOB = {"jobId": "job_abcdef12"}  # アプリが作って送る


def jpeg():
    buf = io.BytesIO()
    Image.new("RGB", (60, 80), "white").save(buf, "JPEG")
    return {"photo": ("p.jpg", buf.getvalue(), "image/jpeg")}


@pytest.fixture
def fakes(monkeypatch):
    rec = {"jobs": [], "pngs": {}}
    monkeypatch.setitem(main.M, "yunet", None)  # startup を走らせないので、読み込み済みのモデルの代わり
    tokens = {"tok": {"uid": "u1", "firebase": {"sign_in_provider": "google.com"}},
              "anon": {"uid": "a1", "firebase": {"sign_in_provider": "anonymous"}}}
    monkeypatch.setattr(main, "verify_token", lambda t: tokens[t] if t in tokens else (_ for _ in ()).throw(ValueError()))
    monkeypatch.setattr(main, "db", lambda: None)
    monkeypatch.setattr(main, "take_quota", lambda db, uid, today: True)

    def write_job(uid, job_id, doc, create=False):
        if create and any(u == uid and j == job_id for u, j, _ in rec["jobs"]):
            raise AlreadyExists("exists")
        rec["jobs"].append((uid, job_id, doc))

    monkeypatch.setattr(main, "write_job", write_job)
    monkeypatch.setattr(main, "put_png", lambda path, data: rec["pngs"].__setitem__(path, data))
    monkeypatch.setattr(main, "notify_ready", lambda uid, job_id: None)
    return rec


def test_missing_bearer_is_401(fakes):
    r = c.post("/v1/outfits/process", files=jpeg(), data=JOB)
    assert r.status_code == 401
    assert r.json()["error"]["code"] == "unauthenticated"


def test_bad_token_is_401(fakes):
    r = c.post("/v1/outfits/process", files=jpeg(), data=JOB, headers={"Authorization": "Bearer nope"})
    assert r.status_code == 401


def test_returns_job_id_and_writes_job(fakes, monkeypatch):
    def fake_process(img, on_status, **kw):
        assert img.shape == (80, 60, 3)
        on_status("masking", 0.2)
        return {"outfitImage": b"\x89PNG-o", "items": [{"index": 0, "slot": "top", "label": "ニット", "color": "赤",
                                                         "image": b"\x89PNG-0", "points": [[400, 500]]}]}

    monkeypatch.setattr(main, "process", fake_process)
    r = c.post("/v1/outfits/process", files=jpeg(), data=JOB, headers=AUTH)
    assert r.status_code == 200
    assert r.json() == {"jobId": "job_abcdef12", "status": "succeeded"}
    job = "job_abcdef12"
    statuses = [d["status"] for _, j, d in fakes["jobs"] if j == job]
    assert statuses == ["queued", "masking", "succeeded"]
    uid, _, last = fakes["jobs"][-1]
    assert uid == "u1"
    assert last["progress"] == 1
    assert last["result"]["outfitImage"] == f"/v1/jobs/{job}/images/outfit"
    assert last["result"]["items"][0]["image"] == f"/v1/jobs/{job}/images/item-0"
    assert fakes["pngs"] == {f"users/u1/jobs/{job}/outfit.png": b"\x89PNG-o", f"users/u1/jobs/{job}/item-0.png": b"\x89PNG-0"}


def test_face_detected_writes_failed_job(fakes, monkeypatch):
    def fake_process(img, on_status, **kw):
        on_status("masking", 0.2)
        raise ProcessError("face_detected")

    monkeypatch.setattr(main, "process", fake_process)
    r = c.post("/v1/outfits/process", files=jpeg(), data=JOB, headers=AUTH)
    assert r.status_code == 200
    assert r.json() == {"jobId": "job_abcdef12", "status": "failed"}
    last = fakes["jobs"][-1][2]
    assert last["status"] == "failed"
    assert last["progress"] == 0.2
    assert last["error"]["code"] == "face_detected"
    assert "result" not in last
    assert fakes["pngs"] == {}


def test_quota_exceeded_is_429(fakes, monkeypatch):
    monkeypatch.setattr(main, "take_quota", lambda db, uid, today: False)
    r = c.post("/v1/outfits/process", files=jpeg(), data=JOB, headers=AUTH)
    assert r.status_code == 429
    assert r.json()["error"]["code"] == "quota_exceeded"
    assert fakes["jobs"][-1][2]["error"]["code"] == "quota_exceeded"  # 購読しているアプリにも届く


def test_existing_job_id_does_not_take_quota(fakes, monkeypatch):
    taken = []
    monkeypatch.setattr(main, "take_quota", lambda db, uid, today: taken.append(1) or True)
    fakes["jobs"].append(("u1", "job_abcdef12", {"status": "succeeded"}))
    assert c.post("/v1/outfits/process", files=jpeg(), data=JOB, headers=AUTH).status_code == 409
    assert taken == []


def test_missing_photo_is_400(fakes):
    r = c.post("/v1/outfits/process", data=JOB, headers=AUTH)
    assert r.status_code == 400
    assert r.json()["error"]["code"] == "validation"


def test_missing_photo_without_auth_is_401(fakes):
    assert c.post("/v1/outfits/process", data=JOB).status_code == 401


def test_job_store_down_is_500_error_shape(fakes, monkeypatch):
    monkeypatch.setattr(main, "write_job", lambda *a, **k: (_ for _ in ()).throw(RuntimeError("users/u1/jobs/x")))
    r = c.post("/v1/outfits/process", files=jpeg(), data=JOB, headers=AUTH)
    assert r.status_code == 500
    assert r.json()["error"]["code"] == "internal"


def test_failure_save_error_does_not_leak(fakes, monkeypatch):
    real = main.write_job

    def flaky(uid, job_id, doc, create=False):
        if doc["status"] == "failed":
            raise RuntimeError("users/u1/jobs/x")
        real(uid, job_id, doc, create)

    monkeypatch.setattr(main, "write_job", flaky)
    monkeypatch.setattr(main, "process", lambda img, on_status, **kw: (_ for _ in ()).throw(ProcessError("no_person")))
    r = c.post("/v1/outfits/process", files=jpeg(), data=JOB, headers=AUTH)
    assert r.json() == {"jobId": "job_abcdef12", "status": "failed"}


def test_large_photo_is_shrunk_before_decoding(fakes, monkeypatch):
    seen = []
    monkeypatch.setattr(main, "process", lambda img, on_status, **kw: seen.append(img.shape) or {"outfitImage": b"", "items": []})
    buf = io.BytesIO()
    Image.new("RGB", (5000, 2500), "white").save(buf, "JPEG")
    c.post("/v1/outfits/process", files={"photo": ("p.jpg", buf.getvalue(), "image/jpeg")}, data=JOB, headers=AUTH)
    assert max(seen[0][:2]) <= 2048


@pytest.mark.parametrize("data", [{}, {"jobId": "short"}, {"jobId": "job/../../x12345"}, {"jobId": "a" * 65}])
def test_bad_or_missing_job_id_is_400(fakes, data):
    r = c.post("/v1/outfits/process", files=jpeg(), data=data, headers=AUTH)
    assert r.status_code == 400
    assert r.json()["error"]["code"] == "validation"
    assert fakes["jobs"] == []


def test_unreadable_photo_is_400(fakes):
    r = c.post("/v1/outfits/process", files={"photo": ("p.jpg", b"not an image", "image/jpeg")}, data=JOB, headers=AUTH)
    assert r.status_code == 400
    assert r.json()["error"]["code"] == "validation"


def test_existing_job_id_is_409(fakes, monkeypatch):
    monkeypatch.setattr(main, "process", lambda img, on_status, **kw: {"outfitImage": b"", "items": []})
    fakes["jobs"].append(("u1", "job_abcdef12", {"status": "succeeded"}))
    r = c.post("/v1/outfits/process", files=jpeg(), data=JOB, headers=AUTH)
    assert r.status_code == 409
    assert r.json()["error"]["code"] == "conflict"
    assert len(fakes["jobs"]) == 1  # 前の結果を書き換えない


EMULATOR = os.environ.get("FIRESTORE_EMULATOR_HOST", "127.0.0.1:8181")


def _emulator_up():
    try:
        urllib.request.urlopen(f"http://{EMULATOR}/", timeout=1).close()
        return True
    except Exception:
        return False


@pytest.mark.skipif(not _emulator_up(), reason="Firestore のエミュレータが要る (server/api/conftest.py と同じ物)")
def test_take_quota_counts_vision_in_shared_doc(monkeypatch):
    """api の auth.charge と同じ置き場 quotas/{uid}_{日付} の vision を数える。api の数は触らない"""
    from google.cloud import firestore

    monkeypatch.setenv("FIRESTORE_EMULATOR_HOST", EMULATOR)
    monkeypatch.setenv("GOOGLE_CLOUD_PROJECT", "demo-df-hack26-vision")  # api のテスト (demo-df-hack26、毎回全部消す) とデータを分ける
    monkeypatch.setenv("QUOTA_VISION", "2")
    db = firestore.Client()
    uid, today = "t_" + uuid.uuid4().hex, date(2026, 11, 8)  # 毎回別の uid にし、エミュレータは空にしない
    ref = db.collection("quotas").document(f"{uid}_2026-11-08")
    ref.set({"nearby": 5})
    assert main.take_quota(db, uid, today)
    assert main.take_quota(db, uid, today)
    assert not main.take_quota(db, uid, today)
    assert ref.get().to_dict() == {"nearby": 5, "vision": 2}
    assert main.take_quota(db, uid, date(2026, 11, 9))  # 日付が替われば 0 から


def test_anonymous_user_is_403(fakes):
    """匿名はログインし直せば uid を作り直せるので、1 人 1 日の上限が効かない。写真の処理は Google でログインした人だけ"""
    r = c.post("/v1/outfits/process", files=jpeg(), data=JOB, headers={"Authorization": "Bearer anon"})
    assert r.status_code == 403 and r.json()["error"]["code"] == "forbidden"
    assert fakes["jobs"] == []


def test_success_notifies_owner_and_failure_does_not(fakes, monkeypatch):
    """処理が終わったら本人に通知する (アプリを閉じていてもプッシュで届く)。失敗の時は jobs の理由だけ"""
    sent = []
    monkeypatch.setattr(main, "notify_ready", lambda uid, job_id: sent.append((uid, job_id)))
    monkeypatch.setattr(main, "process", lambda img, on_status, **kw: {"outfitImage": b"", "items": []})
    c.post("/v1/outfits/process", files=jpeg(), data=JOB, headers=AUTH)
    assert sent == [("u1", "job_abcdef12")]
    monkeypatch.setattr(main, "process", lambda img, on_status, **kw: (_ for _ in ()).throw(ProcessError("no_person")))
    c.post("/v1/outfits/process", files=jpeg(), data={"jobId": "job_other123"}, headers=AUTH)
    assert sent == [("u1", "job_abcdef12")]


def test_notify_failure_does_not_fail_the_job(fakes, monkeypatch):
    monkeypatch.setattr(main, "notify_ready", lambda uid, job_id: (_ for _ in ()).throw(RuntimeError("fcm down")))
    monkeypatch.setattr(main, "process", lambda img, on_status, **kw: {"outfitImage": b"", "items": []})
    assert c.post("/v1/outfits/process", files=jpeg(), data=JOB, headers=AUTH).json()["status"] == "succeeded"


def test_notify_ready_logs_failed_pushes_without_tokens(monkeypatch, caplog):
    """宛先ごとの失敗の種類をログに出す (api の notify._push と同じ。トークンは出さない)"""
    from firebase_admin import messaging

    class Snap:
        def get(self, k):
            return "tok-secret"

    class Col:
        def add(self, d):
            pass

        def stream(self):
            return [Snap()]

    monkeypatch.setattr(main, "db", lambda: type("D", (), {"collection": lambda self, p: Col()})())
    res = type("R", (), {"success": False, "exception": PermissionError("tok-secret")})()
    monkeypatch.setattr(messaging, "send_each_for_multicast", lambda msg: type("B", (), {"responses": [res]})())
    with caplog.at_level("WARNING"):
        main.notify_ready("u1", "job_1")
    assert "PermissionError" in caplog.text and "tok-secret" not in caplog.text
