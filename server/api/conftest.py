"""テストの共通の準備。Firestore はエミュレータ (firebase.json、127.0.0.1:8181) を使う。

先に立ち上げておく: firebase emulators:start --only firestore --project demo-df-hack26
"""
import os
import urllib.request

import pytest

os.environ.setdefault("FIRESTORE_EMULATOR_HOST", "127.0.0.1:8181")
os.environ.setdefault("GOOGLE_CLOUD_PROJECT", "demo-df-hack26")
PROJECT = os.environ["GOOGLE_CLOUD_PROJECT"]


@pytest.fixture
def db():
    from google.cloud import firestore

    host = os.environ["FIRESTORE_EMULATOR_HOST"]
    req = urllib.request.Request(
        f"http://{host}/emulator/v1/projects/{PROJECT}/databases/(default)/documents", method="DELETE"
    )
    urllib.request.urlopen(req).close()  # テストごとに空にする
    return firestore.Client(project=PROJECT)


class FakeBlobs:
    """Storage の代わり (辞書)。"""

    def __init__(self):
        self.d: dict[str, bytes] = {}

    def get(self, path):
        return self.d.get(path)

    def put(self, path, data, content_type="image/png"):
        self.d[path] = data

    def delete(self, path):
        self.d.pop(path, None)


@pytest.fixture
def blobs():
    from blobs import get_blobs
    from main import app

    fake = FakeBlobs()
    app.dependency_overrides[get_blobs] = lambda: fake
    yield fake
    app.dependency_overrides.pop(get_blobs, None)
