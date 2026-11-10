"""vision のサービス (tasks の V1・V3)。全身写真を受けて pipeline.process に通し、結果を Storage と jobs に書く。

元の写真はリクエストのメモリの中だけで扱い、保存もログもしない (docs/architecture.md の 5 節)。
"""
import time

T0 = time.time()  # 起動の秒数の起点 (ほかの import の前)
import datetime  # noqa: E402
import logging  # noqa: E402
import os  # noqa: E402
import re  # noqa: E402

import numpy as np
from fastapi import FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.responses import JSONResponse
from google.api_core.exceptions import AlreadyExists
from PIL import Image, ImageOps

from pipeline import MAX_SIDE, ProcessError, process

app = FastAPI(title="vision")
PROJECT = os.environ.get("GOOGLE_CLOUD_PROJECT", "project-10522535-9db8-40c0-a68")
BUCKET = os.environ.get("STORAGE_BUCKET", f"{PROJECT}.firebasestorage.app")
JST = datetime.timezone(datetime.timedelta(hours=9))
MESSAGES = {
    "face_detected": "顔が見えているため公開できません。撮りなおしてください",
    "no_person": "人が写っていません。全身が入るように撮りなおしてください",
    "ai_failed": "服を読み取れませんでした。もう一度お試しください",
    "internal": "処理に失敗しました。もう一度お試しください",
    "quota_exceeded": "今日の回数の上限に達しました",
}
LOAD: dict[str, float] = {}
M: dict[str, object] = {}


def _lap(name: str, t: float) -> float:
    now = time.time()
    LOAD[name] = round(now - t, 2)
    return now


def load_local() -> None:
    """isnet・SAM・YuNet を読む (ビルドの時の確かめからも呼ぶ)。import の秒数も分けて LOAD に入れる。"""
    t = time.time()
    import torch

    t = _lap("importTorch", t)
    import cv2
    from rembg import new_session

    t = _lap("importRembg", t)
    from transformers import Sam2Model, Sam2Processor

    t = _lap("importSam", t)
    torch.set_num_threads(int(os.environ.get("THREADS", "4")))
    M["isnet"] = new_session("isnet-general-use")
    t = _lap("isnet", t)
    M["sam_proc"] = Sam2Processor.from_pretrained("facebook/sam2.1-hiera-tiny")
    M["sam"] = Sam2Model.from_pretrained("facebook/sam2.1-hiera-tiny").eval()
    t = _lap("sam", t)
    M["yunet"] = cv2.FaceDetectorYN.create(
        os.path.join(os.environ.get("MODELS_DIR", "/models"), "yunet.onnx"), "", (320, 320)
    )
    _lap("yunet", t)


@app.on_event("startup")
def load_models() -> None:
    LOAD["beforeStartup"] = round(time.time() - T0, 2)  # main の import と uvicorn の用意
    load_local()
    t = time.time()
    import firebase_admin
    from google import genai

    firebase_admin.initialize_app(options={"storageBucket": BUCKET})
    M["gemini"] = genai.Client(vertexai=True, project=PROJECT, location="global")
    _lap("clients", t)
    LOAD["total"] = round(time.time() - T0, 2)
    print(f"startup loadSec {LOAD}", flush=True)  # 配備の後に Cloud Logging で内訳を見るため


@app.get("/health")  # /healthz は Cloud Run の予約の道でアプリに届かない
def health() -> dict:
    return {"ok": True, "loadSec": LOAD, "cpus": os.cpu_count()}


# --- 外とのやり取り (テストで差し替える) ---


def verify_token(token: str) -> dict:
    from firebase_admin import auth

    return auth.verify_id_token(token)


def db():
    from firebase_admin import firestore

    return firestore.client()


def take_quota(db, uid: str, today: datetime.date) -> bool:
    """quotas/{uid}_{日付} の vision を 1 足す (api の auth.charge と同じ置き場と形)。上限を超えるなら足さず False。"""
    from google.cloud import firestore

    limit = int(os.environ.get("QUOTA_VISION", "20"))
    ref = db.collection("quotas").document(f"{uid}_{today.isoformat()}")

    @firestore.transactional
    def bump(tx) -> bool:
        used = (ref.get(transaction=tx).to_dict() or {}).get("vision", 0)
        if used >= limit:
            return False
        tx.set(ref, {"vision": used + 1}, merge=True)
        return True

    return bump(db.transaction())


def write_job(uid: str, job_id: str, doc: dict, create: bool = False) -> None:
    """create なら、同じ jobId が既にある時に AlreadyExists を投げる。"""
    ref = db().document(f"users/{uid}/jobs/{job_id}")
    ref.create(doc) if create else ref.set(doc)


def put_png(path: str, data: bytes) -> None:
    from firebase_admin import storage

    storage.bucket().blob(path).upload_from_string(data, content_type="image/png")


def notify_ready(uid: str, job_id: str) -> None:
    """処理が終わった通知を置き、本人の端末へプッシュする (api の notify.py と同じ置き場と形。プッシュには種類と短い文だけ)。"""
    from firebase_admin import messaging
    from google.cloud import firestore

    d, text = db(), "コーデの処理が終わりました。服を確かめて登録してください"
    d.collection(f"users/{uid}/notifications").add(
        {"type": "outfit_ready", "text": text, "createdAt": firestore.SERVER_TIMESTAMP, "read": False, "jobId": job_id})
    tokens = [s.get("token") for s in d.collection(f"users/{uid}/devices").stream() if s.get("token")]
    if tokens:
        res = messaging.send_each_for_multicast(messaging.MulticastMessage(
            tokens=tokens, notification=messaging.Notification(title="WEARBY", body=text), data={"type": "outfit_ready", "jobId": job_id}))
        for r in res.responses:
            if not r.success:  # 種類だけ (トークンはログに出さない)
                logging.warning("push failed: %s", type(r.exception).__name__)


# --- 口 ---


def error(status: int, code: str, message: str) -> JSONResponse:
    return JSONResponse({"error": {"code": code, "message": message}}, status_code=status)


def _run(img: np.ndarray, on_status) -> dict:
    from models import gemini_items, sam_embed, sam_masks
    from rembg import remove

    return process(
        img,
        remove_bg=lambda im: np.array(remove(Image.fromarray(im), session=M["isnet"], only_mask=True)),
        detector=M["yunet"],
        ask_gemini=lambda im: gemini_items(M["gemini"], im),
        sam=lambda im, items, emb: sam_masks(M["sam_proc"], M["sam"], im, items, emb),
        sam_embed=lambda im: sam_embed(M["sam_proc"], M["sam"], im),
        on_status=on_status,
    )


@app.post("/v1/outfits/process")
def process_outfit(photo: UploadFile | None = File(None), jobId: str = Form(""), authorization: str = Header(default="")):  # noqa: N803
    """リクエストの中で処理し、進み具合をアプリが作った users/{uid}/jobs/{jobId} に書く (アプリは送る前に購読を始める)。

    処理が終わったら 200 で jobId と結果の status を返す。失敗も 200 で、理由は jobs に書く。
    """
    if not authorization.startswith("Bearer "):
        return error(401, "unauthenticated", "ログインしてください")
    try:
        decoded = verify_token(authorization[7:])
    except Exception:
        return error(401, "unauthenticated", "ログインしてください")
    if decoded.get("firebase", {}).get("sign_in_provider") == "anonymous":  # 匿名は uid を作り直せて、上限が効かない
        return error(403, "forbidden", "Google でログインしてください")
    uid = decoded["uid"]
    if not re.fullmatch(r"[A-Za-z0-9_-]{8,64}", jobId):
        return error(400, "validation", "jobId の形が違います")
    if photo is None:
        return error(400, "validation", "写真を付けてください")
    try:
        im = Image.open(photo.file)
        im.thumbnail((MAX_SIDE, MAX_SIDE))  # 展開する前に縮める (JPEG は縮めて読む)。大きな写真 1 枚でメモリを食わないため
        img = np.array(ImageOps.exif_transpose(im).convert("RGB"))  # 端末の写真は EXIF で向きを持つ
    except Exception:
        return error(400, "validation", "写真を読み込めませんでした")

    state = {"progress": 0.0, "status": "queued"}

    def save(status: str, progress: float, create: bool = False, **extra) -> None:
        state["progress"], state["status"] = progress, status
        now = datetime.datetime.now(JST).isoformat(timespec="seconds")
        write_job(uid, jobId, {"status": status, "progress": progress, "updatedAt": now, **extra}, create=create)

    try:
        save("queued", 0.0, create=True)  # 回数より先に作る。同じ jobId の送り直しで回数を減らさない
        if not take_quota(db(), uid, datetime.datetime.now(JST).date()):
            save("failed", 0.0, error={"code": "quota_exceeded", "message": MESSAGES["quota_exceeded"]})
            return error(429, "quota_exceeded", MESSAGES["quota_exceeded"])
    except AlreadyExists:
        return error(409, "conflict", "この jobId は使用済みです")
    except Exception as e:
        logging.error("job start failed: %s", type(e).__name__)  # 中身は uid や path を含みうるので型の名前だけ
        return error(500, "internal", MESSAGES["internal"])
    code = None
    try:
        res = _run(img, save)
        base = f"users/{uid}/jobs/{jobId}"
        put_png(f"{base}/outfit.png", res["outfitImage"])
        items = []
        for it in res["items"]:
            put_png(f"{base}/item-{it['index']}.png", it["image"])
            items.append(it | {"image": f"/v1/jobs/{jobId}/images/item-{it['index']}"})
        save("succeeded", 1, result={"outfitImage": f"/v1/jobs/{jobId}/images/outfit", "items": items})
        try:
            notify_ready(uid, jobId)
        except Exception as e:  # 通知が落ちても処理の結果は残す。アプリは jobs を購読している
            logging.warning("notify failed: %s", type(e).__name__)
    except ProcessError as e:
        code = e.code
    except Exception as e:
        logging.error("process failed: %s", type(e).__name__)
        code = "internal"
    if code:
        try:
            save("failed", state["progress"], error={"code": code, "message": MESSAGES[code]})
        except Exception as e:
            logging.error("job save failed: %s", type(e).__name__)
            state["status"] = "failed"
    return {"jobId": jobId, "status": state["status"]}
