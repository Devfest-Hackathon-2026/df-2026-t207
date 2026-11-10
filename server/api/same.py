"""同じ服の判定 (GET /v1/jobs/{jobId}/same-items、tasks の L1、docs/architecture.md の 3.6)。

処理の結果の服ごとに、本人の手持ちの同じ区分の服を、切り抜きのベクトルで近い順に 5 着まで集め、Gemini に同じ 1 着を選ばせる。
1 人の手持ちは多くて数十着なので、Firestore のベクトルの索引は使わずにここで比べる。検索は必ず本人の手持ちだけ。
"""
import math
import re
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from google.cloud import firestore

import ai
from auth import User, charge, current_user, google_uid
from blobs import Blobs, get_blobs
from match import call_ai
from nearby import garment
from outfits import JOB_RE, item_body
from routes_me import JST, get_db

TOP_K = 5
router = APIRouter()


def _cos(a: list[float], b: list[float]) -> float:
    return sum(x * y for x, y in zip(a, b)) / ((math.sqrt(sum(x * x for x in a)) * math.sqrt(sum(y * y for y in b))) or 1)


@router.get("/v1/jobs/{jobId}/same-items")
def same_items(jobId: str, user: User = Depends(current_user), db: firestore.Client = Depends(get_db),  # noqa: N803
               blobs: Blobs = Depends(get_blobs)):
    uid = google_uid(user)
    job = db.document(f"users/{uid}/jobs/{jobId}").get().to_dict() if re.fullmatch(JOB_RE, jobId) else None
    if job is None:
        raise HTTPException(404, {"code": "not_found", "message": "処理の記録が見つかりません"})
    if job.get("status") != "succeeded":
        raise HTTPException(409, {"code": "not_ready", "message": "処理が終わっていません"})
    mine = [(s.id, s.to_dict()) for s in db.collection(f"users/{uid}/wardrobeItems").stream()]
    mine = [(wid, d) for wid, d in mine if d.get("vector")]
    todo = [it for it in job["result"]["items"] if any(d.get("slot") == it.get("slot") for _, d in mine)]
    if not todo:
        return {"items": []}
    charge(db, uid, "same", datetime.now(JST).date())

    def one(it: dict):
        png = blobs.get(f"users/{uid}/jobs/{jobId}/item-{it['index']}.png")
        if png is None:
            return None
        vec = call_ai(ai.embed, png)
        near = sorted((m for m in mine if m[1].get("slot") == it.get("slot")), key=lambda m: _cos(vec, m[1]["vector"]), reverse=True)[:TOP_K]
        cands = [(wid, garment(d), blobs.get(d.get("image", ""))) for wid, d in near]
        cands = [c for c in cands if c[2] is not None]
        got = call_ai(ai.pick_same, garment(it), png, cands) if cands else None
        hit = dict(near).get(got["wardrobeItemId"]) if got else None
        if hit is None:  # どれでもない、か、渡していない id を返した
            return None
        return {"index": it["index"], "wardrobeItem": item_body(got["wardrobeItemId"], hit), "reason": got.get("reason", "")}

    with ThreadPoolExecutor(4) as ex:  # 服ごとに数秒かかるので並べる
        return {"items": [r for r in ex.map(one, todo) if r]}
