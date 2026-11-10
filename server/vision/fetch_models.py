"""ビルドの時にモデルの重みを /models に揃える (起動を速くするため、重みはイメージに入れる)。

cloudbuild.yaml が Storage の build-models/ から重みを落とした後に走り、無い物と hash の違う物だけを取り直す
(isnet は rembg が md5 で確かめる、YuNet はここで sha256 を確かめる)。
"""
import hashlib
import os
import time
import urllib.request

MODELS = os.environ.get("MODELS_DIR", "/models")
os.makedirs(MODELS, exist_ok=True)


def retry(f, tries: int = 4):
    """GitHub の配布が 504 を返すことがある (2026-11-08 の Cloud Build で続けて落ちた)。間を空けて取り直す。"""
    for i in range(tries):
        try:
            return f()
        except Exception as e:
            if i == tries - 1:
                raise
            print(f"retry {i + 1}: {type(e).__name__}: {e}", flush=True)
            time.sleep(15 * (i + 1))


t = time.time()
# isnet (rembg) -> $U2NET_HOME
from rembg import new_session  # noqa: E402

retry(lambda: new_session("isnet-general-use"))
print(f"isnet ok {time.time() - t:.1f}s", flush=True)
t = time.time()

# SAM 2.1 tiny (Apache-2.0) -> $HF_HOME
from transformers import Sam2Model, Sam2Processor  # noqa: E402

retry(lambda: Sam2Processor.from_pretrained("facebook/sam2.1-hiera-tiny"))
retry(lambda: Sam2Model.from_pretrained("facebook/sam2.1-hiera-tiny"))
print(f"sam ok {time.time() - t:.1f}s", flush=True)
t = time.time()

# YuNet (OpenCV Zoo、MIT)。顔の確かめ (安全の要) に使うので、版を sha256 で固定する。URL を替える時は hash も替える
YUNET_URL = "https://github.com/opencv/opencv_zoo/raw/main/models/face_detection_yunet/face_detection_yunet_2023mar.onnx"
YUNET_SHA256 = "8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4"
yunet = os.path.join(MODELS, "yunet.onnx")
sha = lambda: hashlib.sha256(open(yunet, "rb").read()).hexdigest() if os.path.exists(yunet) else None  # noqa: E731
if sha() != YUNET_SHA256:
    retry(lambda: urllib.request.urlretrieve(YUNET_URL, yunet))
    assert sha() == YUNET_SHA256, "YuNet の hash が違う (504 の HTML か、別の版)"
print(f"yunet ok {time.time() - t:.1f}s", flush=True)
