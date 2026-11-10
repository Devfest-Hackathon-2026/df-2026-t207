"""自分の写真と着用イメージ (PUT/DELETE /v1/me/photo、POST /v1/tryon、GET /v1/tryon/{tryonId}/image、tasks の S4)。

- 写真はアプリ (Web はブラウザ) のカメラで撮った物だけ (capturedWith=camera)
- 着用イメージの手持ちは acting_uid の物。写真は本人の物があればそれ、無ければ acting_uid の物。記録は本人の uid
- 匿名 (Web デモの審査員) の写真と着用イメージは anon/{uid}/ の下に置く。バケットの決まりで 1〜2 日で消える
- 画像は本人にだけ返す
"""
import io
import re
import secrets
from datetime import datetime

from fastapi import APIRouter, Depends, File, Form, HTTPException, Response, UploadFile
from google.cloud import firestore
from PIL import Image, ImageOps
from pydantic import BaseModel, Field

import ai
from auth import User, acting_uid, charge_user, current_user
from blobs import Blobs, get_blobs
from cards import not_found
from match import call_ai, precomputed, seen_item
from outfits import item_ref
from routes_me import JST, get_db

LABEL = "AI による着用イメージ"
MAX_PHOTO = 10 * 2**20
TRYON_ID = re.compile(r"t_[\w-]{1,40}")
router = APIRouter()


def own_dir(user: User) -> str:
    return f"anon/{user.uid}" if user.is_anonymous else f"users/{user.uid}"


def bad(message: str) -> HTTPException:
    return HTTPException(400, {"code": "validation", "message": message})


@router.put("/v1/me/photo", status_code=204)
def put_photo(photo: UploadFile = File(), capturedWith: str = Form(), user: User = Depends(current_user),
              db: firestore.Client = Depends(get_db), blobs: Blobs = Depends(get_blobs)):
    if capturedWith != "camera":
        raise bad("アプリのカメラで撮った写真だけ使えます")
    data = photo.file.read(MAX_PHOTO + 1)
    try:
        if len(data) > MAX_PHOTO:
            raise ValueError
        im = Image.open(io.BytesIO(data))
        if im.format not in ("JPEG", "MPO"):  # 端末のカメラの JPEG は MPO と読まれることがある
            raise ValueError
        if im.width * im.height > 40_000_000:  # 展開する前に止める (画素数の大きい画像でメモリが溢れないように)
            raise ValueError
        im.draft("RGB", (2048, 2048))  # JPEG は縮めて展開する (大きな写真で 512Mi を使い切らないように)
        im = ImageOps.exif_transpose(im).convert("RGB")
        im.thumbnail((2048, 2048))
    except Exception:
        raise bad("10MB までの JPEG にしてください")
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=90)  # 書き直して EXIF (位置など) を落とす
    blobs.put(f"{own_dir(user)}/photo.jpg", buf.getvalue(), "image/jpeg")
    if not user.is_anonymous:
        db.document(f"users/{user.uid}").set({"hasPhoto": True}, merge=True)
    return Response(status_code=204)


@router.delete("/v1/me/photo", status_code=204)
def delete_photo(user: User = Depends(current_user), db: firestore.Client = Depends(get_db), blobs: Blobs = Depends(get_blobs)):
    blobs.delete(f"{own_dir(user)}/photo.jpg")
    if not user.is_anonymous:
        db.document(f"users/{user.uid}").set({"hasPhoto": False}, merge=True)
    return Response(status_code=204)


class TryOnBody(BaseModel):
    cardId: str
    cardItemId: str
    wardrobeItemIds: list[str] = Field(max_length=3)


@router.post("/v1/tryon")
def tryon(body: TryOnBody, user: User = Depends(current_user), db: firestore.Client = Depends(get_db),
          blobs: Blobs = Depends(get_blobs)):
    now = datetime.now(JST)
    item, owner = seen_item(db, user, body.cardId, body.cardItemId, now)
    me = acting_uid(user)
    mine = [item_ref(db, me, w).get().to_dict() for w in body.wardrobeItemIds]
    if not all(mine):
        raise not_found()
    tid = "t_" + secrets.token_urlsafe(9)
    own = blobs.get(f"{own_dir(user)}/photo.jpg") if user.is_anonymous else None  # 審査員が自分の写真を置いていれば、それで作る
    pre = None if own else precomputed(db, "tryon", me, owner, [item["_id"], *sorted(body.wardrobeItemIds)])
    if pre:
        path = pre["image"]
    else:
        photo = own or blobs.get(f"users/{me}/photo.jpg")
        if photo is None:
            raise HTTPException(409, {"code": "photo_required", "message": "着用イメージには、あなたの全身写真が要ります"})
        garments = [blobs.get(d.get("image", "")) for d in [item, *mine]]
        if None in garments:
            raise not_found()
        charge_user(db, user, "tryon", now.date())
        png = call_ai(ai.make_tryon, photo, garments)
        path = f"{own_dir(user)}/tryons/{tid}.png"
        blobs.put(path, png)
    db.document(f"users/{user.uid}/tryons/{tid}").set({"image": path, "precomputed": bool(pre), "createdAt": now})
    return {"tryonId": tid, "image": f"/v1/tryon/{tid}/image", "label": LABEL, "precomputed": bool(pre),
            "generatedAt": now.isoformat()}


@router.get("/v1/tryon/{tryonId}/image")
def tryon_image(tryonId: str, user: User = Depends(current_user), db: firestore.Client = Depends(get_db),
                blobs: Blobs = Depends(get_blobs)):
    rec = db.document(f"users/{user.uid}/tryons/{tryonId}").get().to_dict() if TRYON_ID.fullmatch(tryonId) else None
    png = blobs.get(rec["image"]) if rec else None
    if png is None:
        raise not_found()
    return Response(png, media_type="image/png", headers={"Cache-Control": "private, no-store"})
