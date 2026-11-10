"""Gemini と SAM 2.1 の本物の呼び出し (tasks の V3)。手元の試験 (seg-bench の gemini_test2.py と sam_test2.py) を関数にした物。

自動のテストは無い (Gemini を呼ぶため)。確かめ方は seg-bench の try_v3.py。
"""
import io
from typing import Literal

import numpy as np
import torch
from google.genai import types
from PIL import Image
from pydantic import BaseModel

MODEL = "gemini-3.8-flash"

PROMPT = """List every clothing item and accessory worn by the person in this photo.
The face is blurred (or the head is painted gray) and the background is white on purpose; ignore them and do not list them as items.
Include inner layers that are partly visible (e.g. a sweater under a vest, a shirt under a jacket).
A pair of shoes (or socks, earrings, gloves) is ONE item: return it once, with a box covering both and points on both.
For each item return:
- slot: one of outer, top, bottom, dress, shoes, bag, accessory
- category: the Fashionpedia category name in English (e.g. jacket, sweater, pants, shoe)
- label: a short name in Japanese (e.g. デニムジャケット)
- layer: outer, inner or single
- color, pattern, materialGuess: short Japanese words (e.g. ライトブルー, 無地, デニム)
- box_2d: [ymin, xmin, ymax, xmax] normalized to 0-1000, covering only the visible part of the item
- points: 2 or 3 points [y, x] normalized to 0-1000 that lie clearly ON this item and NOT on any other item (e.g. on a visible sleeve of an inner sweater)"""


class Item(BaseModel):
    slot: Literal["outer", "top", "bottom", "dress", "shoes", "bag", "accessory"]
    category: str
    label: str
    layer: Literal["outer", "inner", "single"]
    color: str
    pattern: str
    materialGuess: str
    box_2d: list[int]
    points: list[list[int]]


def gemini_items(client, img: np.ndarray) -> list[dict]:
    """頭と背景を消した画像 (RGB) から、服ごとの区分・属性・枠・点を返す。形は response_schema で決める。"""
    buf = io.BytesIO()
    Image.fromarray(img).save(buf, "JPEG", quality=90)
    r = client.models.generate_content(
        model=MODEL,
        contents=[types.Part.from_bytes(data=buf.getvalue(), mime_type="image/jpeg"), PROMPT],
        config=types.GenerateContentConfig(temperature=0.2, response_mime_type="application/json", response_schema=list[Item]),
    )
    if r.parsed is None:
        raise ValueError("Gemini の応答が形に合わない")
    return [it.model_dump() for it in r.parsed]


def sam_embed(proc, model, img: np.ndarray):
    """SAM の画像の読み込み (約 3 秒)。Gemini の応答待ちの間に呼ぶ。"""
    with torch.no_grad():
        return model.get_image_embeddings(proc(images=Image.fromarray(img), return_tensors="pt")["pixel_values"])


def sam_masks(proc, model, img: np.ndarray, items: list[dict], embeddings) -> list[np.ndarray]:
    """服ごとに、枠とその服の点を「含める」、枠の中にあるほかの服の点を「除く」として渡し、マスク (bool) を返す。"""
    pil = Image.fromarray(img)
    h, w = img.shape[:2]
    xy = lambda p: [p[1] / 1000 * w, p[0] / 1000 * h]  # noqa: E731  [y, x] の 0〜1000 → 画素の [x, y]
    masks = []
    for it in items:
        y0, x0, y1, x1 = it["box_2d"]
        box = [x0 / 1000 * w, y0 / 1000 * h, x1 / 1000 * w, y1 / 1000 * h]
        pts, lbs = [xy(p) for p in it["points"]], [1] * len(it["points"])
        for o in items:
            if o is not it:
                for x, y in map(xy, o["points"]):
                    if box[0] < x < box[2] and box[1] < y < box[3]:
                        pts.append([x, y])
                        lbs.append(0)
        kw = dict(images=pil, input_boxes=[[box]], return_tensors="pt")
        if pts:
            kw |= dict(input_points=[[pts]], input_labels=[[lbs]])
        inp = proc(**kw)
        with torch.no_grad():
            out = model(image_embeddings=embeddings, **{k: v for k, v in inp.items() if k != "pixel_values"}, multimask_output=False)
        masks.append(proc.post_process_masks(out.pred_masks, inp["original_sizes"])[0][0][0].numpy() > 0)
    return masks
