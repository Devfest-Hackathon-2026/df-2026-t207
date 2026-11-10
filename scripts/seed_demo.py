"""デモの人物の投入 (tasks の D2)。素材の写真を vision と同じ処理に手元で通し、Firestore と Storage に直接入れる。

素材のフォルダ (リポジトリには入れない):
    viewer/photo.jpg        見る人 (Web の審査員が成り代わる人) の全身写真。着用イメージに使う
    viewer/outfit-*.jpg     見る人の着姿。ここから手持ちを切り抜く
    people/<名前>.jpg       見られる側の着姿 (1 人 1 枚)

使い方 (df-hack26 で、seg-bench の venv):
    python scripts/seed_demo.py <素材のフォルダ> [--prefix demo]
入れ直すと、その uid の前の手持ち・着姿・画像は消える。最後に api に入れる環境変数を表示する (配備は手で)。
デモの人物はログインしないので、Firebase Auth のアカウントは作らない (uid は Firestore の置き場の名前だけ)。
"""
import argparse
import io
import os
import re
import secrets
import sys
from datetime import datetime
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "server" / "api"))

from nearby import garment  # noqa: E402
from routes_me import JST  # noqa: E402


def _clear(db, blobs, uid: str) -> None:
    for sub in ("wardrobeItems", "dailyOutfits", "jobs"):
        for d in db.collection(f"users/{uid}/{sub}").stream():
            d.reference.delete()
    for path in [p for p in getattr(blobs, "keys", lambda: [])() if p.startswith(f"users/{uid}/")]:  # 偽物の Storage
        blobs.delete(path)
    if hasattr(blobs, "bucket"):  # 本物の Storage
        for b in blobs.bucket.list_blobs(prefix=f"users/{uid}/"):
            b.delete()


def _register(db, blobs, uid: str, path: Path, run_vision, now: datetime) -> tuple[list[str], str] | None:
    """写真 1 枚を処理して手持ちに足す。返すのは足した手持ちの id と、着姿の Storage の path。処理が止まったら None。"""
    img = np.array(ImageOps.exif_transpose(Image.open(path)).convert("RGB"))
    try:
        res = run_vision(img)
    except Exception as e:  # 顔が残った (face_detected) など。その写真だけ飛ばす
        print(f"  {path.name}: 飛ばした ({getattr(e, 'code', None) or e})")
        return None
    base = f"users/{uid}/jobs/seed_{secrets.token_hex(6)}"
    blobs.put(f"{base}/outfit.png", res["outfitImage"])
    ids = []
    for it in res["items"]:
        blobs.put(f"{base}/item-{it['index']}.png", it["image"])
        wid = "w_" + secrets.token_urlsafe(9)
        db.document(f"users/{uid}/wardrobeItems/{wid}").set(
            {**garment(it), "image": f"{base}/item-{it['index']}.png", "memo": "", "createdAt": now, "jobId": base.rsplit("/", 1)[1]})
        ids.append(wid)
    print(f"  {path.name}: {[it.get('label') for it in res['items']]}")
    return ids, f"{base}/outfit.png"


def daily(db, uid: str, ids: list[str], outfit: str) -> dict:
    """その日のコーデの文書。api の登録と同じく、投稿時点の写し (snapshot) と着姿の画像の口を持つ。"""
    from outfits import api_image, snap

    items = [db.document(f"users/{uid}/wardrobeItems/{i}").get().to_dict() for i in ids]
    return {"items": ids, "image": outfit, "visibility": "nearby", "outfitImage": api_image(outfit),
            "snapshot": [snap(i, w) for i, w in zip(ids, items)], "itemNotes": [], "jobId": outfit.rsplit("/", 2)[-2]}


def seed(db, blobs, folder: Path, prefix: str, run_vision, now: datetime) -> dict:
    folder = Path(folder)
    day = now.date().isoformat()
    people = sorted((folder / "people").glob("*.jpg"))
    owners = []
    for path in people:
        uid = f"{prefix}-{re.sub(r'[^a-z0-9]+', '-', path.stem.lower()).strip('-')}"
        print(uid)
        _clear(db, blobs, uid)
        got = _register(db, blobs, uid, path, run_vision, now)
        if got is None:
            continue
        ids, outfit = got
        db.document(f"users/{uid}").set({"displayName": path.stem, "demo": True})
        db.document(f"users/{uid}/dailyOutfits/{day}").set(daily(db, uid, ids, outfit))
        owners.append(uid)

    viewer = f"{prefix}-viewer"
    print(viewer)
    _clear(db, blobs, viewer)
    for path in sorted((folder / "viewer").glob("outfit-*.jpg")):
        _register(db, blobs, viewer, path, run_vision, now)
    im = ImageOps.exif_transpose(Image.open(folder / "viewer" / "photo.jpg")).convert("RGB")
    im.thumbnail((2048, 2048))
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=90)
    blobs.put(f"users/{viewer}/photo.jpg", buf.getvalue(), "image/jpeg")
    db.document(f"users/{viewer}").set({"displayName": "デモの見る人", "demo": True, "hasPhoto": True})
    return {"DEMO_UIDS": ",".join(owners), "WEB_DEMO_UIDS": ",".join(owners), "DEMO_VIEWER_UID": viewer}


def real_vision():
    """手元で vision の pipeline.process を本物の isnet・YuNet・Gemini・SAM で動かす関数を返す。"""
    import cv2
    import torch
    from google import genai
    from rembg import new_session, remove
    from transformers import Sam2Model, Sam2Processor

    sys.path.insert(0, str(HERE.parent / "server" / "vision"))
    from models import gemini_items, sam_embed, sam_masks
    from pipeline import process

    torch.set_num_threads(4)
    det = cv2.FaceDetectorYN.create(os.path.expandvars(r"%LOCALAPPDATA%\df-hack26\models\yunet.onnx"), "", (320, 320))
    isnet = new_session("isnet-general-use")
    proc = Sam2Processor.from_pretrained("facebook/sam2.1-hiera-tiny")
    sam = Sam2Model.from_pretrained("facebook/sam2.1-hiera-tiny").eval()
    client = genai.Client(vertexai=True, project=os.environ["GOOGLE_CLOUD_PROJECT"], location="global")
    return lambda img: process(
        img,
        remove_bg=lambda im: np.array(remove(Image.fromarray(im), session=isnet, only_mask=True)),
        detector=det,
        ask_gemini=lambda im: gemini_items(client, im),
        sam=lambda im, its, emb: sam_masks(proc, sam, im, its, emb),
        sam_embed=lambda im: sam_embed(proc, sam, im),
    )


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("folder", type=Path)
    ap.add_argument("--prefix", default="demo")
    a = ap.parse_args()
    os.environ.setdefault("GOOGLE_CLOUD_PROJECT", "project-10522535-9db8-40c0-a68")
    from google.cloud import firestore

    from blobs import get_blobs

    env = seed(firestore.Client(), get_blobs(), a.folder, a.prefix, real_vision(), datetime.now(JST))
    # 値に「,」が入るので、gcloud の区切りを「;」に替える書き方で出す
    print("\napi に入れる環境変数 (gcloud run deploy api ... --update-env-vars に渡す):")
    print("  ^;^" + ";".join(f"{k}={v}" for k, v in env.items()))
