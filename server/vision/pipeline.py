"""全身写真 1 枚の処理の本体 (tasks の V3)。docs/architecture.md の 3.1 の 2〜6 段。

元の写真はこの関数のメモリの中だけで扱い、保存もログもしない。Gemini と SAM は引数で受ける (テストで偽物に替えるため)。
"""
from concurrent.futures import ThreadPoolExecutor

import cv2
import numpy as np

from masking import STEPS, find_faces, head_faces, hide_head, largest_blob, recheck

MAX_SIDE = 2048
MIN_PERSON = 0.01  # 人物の形が画像の 1% 未満なら「人が写っていない」とする
REDO = 2  # 確かめの枠が楕円に一部だけかかる時に、ぼかす所を広げて同じ段をやり直す回数
RECHECK_SCORE = 0.3  # 塗った後の顔の確かめは安全網なので、塗る前 (0.6) より厳しく。誤検出の代償は撮り直しだけ
GARMENT_KEYS = ("slot", "category", "label", "layer", "color", "pattern", "materialGuess")


class ProcessError(Exception):
    def __init__(self, code: str):
        super().__init__(code)
        self.code = code  # face_detected / no_person / ai_failed (docs/api.yaml の Job.error.code)


def _png(rgba: np.ndarray) -> bytes:
    return cv2.imencode(".png", cv2.cvtColor(rgba, cv2.COLOR_RGBA2BGRA))[1].tobytes()


def _clip(item: dict) -> dict | None:
    """Gemini の枠と点 (0〜1000) を画像の中に切り詰める。枠が 4 つの数でなければ None (schema は長さを縛らない)。"""
    if len(item.get("box_2d", [])) != 4:
        return None
    box = [int(v) for v in np.clip(item["box_2d"], 0, 1000)]
    pts = [[int(v) for v in np.clip(p, 0, 1000)] for p in item.get("points", []) if len(p) == 2]
    return dict(item, box_2d=box, points=pts)


def process(img_rgb: np.ndarray, *, remove_bg, detector, ask_gemini, sam, sam_embed, on_status=lambda s, p: None) -> dict:
    """頭を塗り、背景を消し、Gemini で服を見つけ、SAM で切り抜く。

    remove_bg(img) -> 透過 (uint8)、ask_gemini(img) -> 服の list、sam_embed(img) -> 画像の読み込み、sam(img, items, emb) -> マスクの list。
    返り値は Job.result の形で、outfitImage と items[].image は PNG のバイト列。
    """
    h, w = img_rgb.shape[:2]
    if max(h, w) > MAX_SIDE:
        s = MAX_SIDE / max(h, w)
        img_rgb = cv2.resize(img_rgb, (round(w * s), round(h * s)), interpolation=cv2.INTER_AREA)

    # 頭を塗るには人物の形が要るので、背景除去の透過を先に取る
    on_status("masking", 0.2)
    person = largest_blob(remove_bg(img_rgb))
    if person.sum() < MIN_PERSON * person.size:
        raise ProcessError("no_person")
    faces = head_faces(person, find_faces(detector, cv2.cvtColor(img_rgb, cv2.COLOR_RGB2BGR)))
    # 顔をぼかし (顔が無ければ頭を塗り)、背景を白にした物で確かめる。顔が残れば強くぼかし直し、最後は単色 (masking.hide_head)。Gemini と SAM に渡すのはこれだけ
    for step in range(STEPS if faces else 1):
        for _ in range(REDO + 1):
            clean, alpha = hide_head(img_rgb, person, faces, step)
            left, partial = recheck(find_faces(detector, cv2.cvtColor(clean, cv2.COLOR_RGB2BGR), score=RECHECK_SCORE), faces, step, person.shape)
            if not partial:
                break
            faces = faces + partial  # 元の枠が顔の一部だった恐れ。ぼかす所を広げて同じ段をやり直す
        if not left and not partial:  # 自分でぼかした楕円に 9 割以上入る検出は隠し済み
            break
    else:
        raise ProcessError("face_detected")

    # SAM の画像の読み込みを、Gemini の応答待ちに重ねる
    on_status("segmenting", 0.45)
    with ThreadPoolExecutor(1) as ex:
        emb = ex.submit(sam_embed, clean)
        on_status("detecting", 0.6)
        try:
            found = ask_gemini(clean)
        except Exception as e:
            raise ProcessError("ai_failed") from e
        emb = emb.result()

    on_status("cutting", 0.85)
    items = [it for it in map(_clip, found) if it and it["box_2d"][0] < it["box_2d"][2] and it["box_2d"][1] < it["box_2d"][3]]
    masks = sam(clean, items, emb) if items else []
    out = []
    for it, m in zip(items, masks):
        m = m & person
        ys, xs = np.nonzero(m)
        if not len(ys):
            continue
        rgba = np.dstack([clean, m.astype(np.uint8) * 255])[ys.min() : ys.max() + 1, xs.min() : xs.max() + 1]
        g = {k: it[k] for k in GARMENT_KEYS if k in it}
        out.append(g | {"index": len(out), "image": _png(rgba), "points": [{"y": y, "x": x} for y, x in it["points"]]})  # Firestore は配列の中の配列を持てない
    return {"outfitImage": _png(np.dstack([clean, (alpha * 255).round().astype(np.uint8)])), "items": out}
