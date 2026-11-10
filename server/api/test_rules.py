"""Firestore の Security Rules (firestore.rules) の試験。アプリ (Firebase の SDK) からの読み書きを、エミュレータの REST で真似る。

決まり: アプリは本人の文書 (users/{uid} とその下) を読むだけ。書き込みと、ほかの置き場はすべて拒否 (docs/architecture.md の 4 節)。
エミュレータは firebase.json の firestore.rules を読んで立てる。サーバ (Python の SDK) は管理者として扱われ、決まりを通らない。
"""
import base64
import json
import os
import urllib.request

import pytest

HOST = os.environ.get("FIRESTORE_EMULATOR_HOST", "127.0.0.1:8181")
PROJECT = "demo-df-hack26"  # エミュレータが firestore.rules を読むのはこの置き場だけ (別の置き場で流すとこの試験だけ落ちる)
BASE = f"http://{HOST}/v1/projects/{PROJECT}/databases/(default)/documents"


def token(uid: str) -> str:
    """エミュレータは署名の無い ID トークンを受ける"""
    b64 = lambda d: base64.urlsafe_b64encode(json.dumps(d).encode()).rstrip(b"=").decode()  # noqa: E731
    claims = {"sub": uid, "user_id": uid, "aud": PROJECT, "iss": f"https://securetoken.google.com/{PROJECT}",
              "iat": 1, "exp": 4102444800, "auth_time": 1, "firebase": {"sign_in_provider": "google.com"}}
    return f"{b64({'alg': 'none', 'typ': 'JWT'})}.{b64(claims)}."


def req(method: str, path: str, uid: str | None, body: dict | None = None) -> int:
    h = {"Content-Type": "application/json"} | ({"Authorization": f"Bearer {token(uid)}"} if uid else {})
    r = urllib.request.Request(f"{BASE}/{path}", data=json.dumps(body).encode() if body else None, headers=h, method=method)
    try:
        return urllib.request.urlopen(r).status
    except urllib.error.HTTPError as e:
        return e.code


@pytest.fixture(autouse=True)
def seed(db):
    db.document("users/u1").set({"displayName": "a"})
    db.document("users/u1/jobs/job_1").set({"status": "queued"})
    db.document("users/u1/wardrobeItems/w_1").set({"slot": "top"})
    db.document("users/u2/jobs/job_2").set({"status": "queued"})
    db.document("cards/c_1").set({"owner": "u2", "viewer": "u1"})
    db.document("broadcastIds/" + "a" * 22).set({"uid": "u2"})


@pytest.mark.parametrize("path", ["users/u1", "users/u1/jobs/job_1", "users/u1/wardrobeItems/w_1"])
def test_owner_can_read_own_docs(path):
    assert req("GET", path, "u1") == 200


@pytest.mark.parametrize("path,uid", [("users/u2/jobs/job_2", "u1"), ("users/u1/jobs/job_1", None),
                                      ("cards/c_1", "u1"), ("broadcastIds/" + "a" * 22, "u2")])
def test_others_docs_and_server_only_places_are_denied(path, uid):
    assert req("GET", path, uid) == 403


def test_owner_cannot_write_even_own_docs():
    assert req("PATCH", "users/u1/jobs/job_1", "u1", {"fields": {"status": {"stringValue": "succeeded"}}}) == 403
    assert req("PATCH", "users/u1", "u1", {"fields": {"publishGen": {"stringValue": "x"}}}) == 403
