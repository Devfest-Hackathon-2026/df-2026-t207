"""Storage の読み書き。テストでは conftest の FakeBlobs に替える。"""
import os
from functools import lru_cache

PROJECT = os.environ.get("GOOGLE_CLOUD_PROJECT", "project-10522535-9db8-40c0-a68")
BUCKET = os.environ.get("STORAGE_BUCKET", f"{PROJECT}.firebasestorage.app")


class Blobs:
    def __init__(self, bucket):
        self.bucket = bucket

    def get(self, path: str) -> bytes | None:
        from google.api_core.exceptions import NotFound

        try:
            return self.bucket.blob(path).download_as_bytes()
        except NotFound:
            return None

    def put(self, path: str, data: bytes, content_type: str = "image/png") -> None:
        self.bucket.blob(path).upload_from_string(data, content_type=content_type)

    def delete(self, path: str) -> None:
        from google.api_core.exceptions import NotFound

        try:
            self.bucket.blob(path).delete()
        except NotFound:
            pass


@lru_cache
def get_blobs() -> Blobs:
    from google.cloud import storage

    return Blobs(storage.Client().bucket(BUCKET))
