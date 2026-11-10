"""頭を隠す処理と、背景除去の結果から本人だけを残す処理 (tasks の V2)。

他人に見せる着姿と Gemini に送る画像は、必ずここを通す (docs/architecture.md の 3.1)。
"""
import threading

import cv2
import numpy as np

GRAY = 128
TOP_BAND = 1 / 5  # 顔が見つからない時に、人物の形の上から何割を頭として塗るか (帯の中の人物の形を全幅で)
FACE_SCALE = 2.0  # 単色で塗る時に、顔の枠をどれだけ広げた楕円にするか (1.8 では c9 の髪の角が残り、確かめで 0.34 が出た)
# ぼかしの段: (sigma を顔の枠の高さに対する割合で, 楕円の広げ方, 白黒へ寄せる割合)。確かめで顔が残るたびに次の段へ。
# 1 段目は目から顎までを色のままぼかす (sigma は顔の高さの 12%、目鼻口の幅より大きいので形は残らない)。
# 横顔では、ぼけた肌色とその周りの髪を YuNet が顔と見るので、2・3 段目は楕円を広げ、白黒に寄せる (Commons の写真で決めた)
BLUR = ((0.12, 1.25, 0.0), (0.25, 2.0, 0.5), (0.25, 2.0, 1.0))
FACE_TOP = 0.4  # 本人の顔はふつう人物の形の上 4 割にある。どの顔もその下なら、服の柄の顔だけを拾った恐れがあるので頭も塗る
STEPS = len(BLUR) + 2  # ぼかしの段の後に、顔の楕円を単色、最後に頭の形 + 顔の楕円を単色
HIDDEN = 0.9  # 確かめの検出の枠がこの割合以上ぼかした楕円に入っていれば隠し済み
BLOB_AREA, BLOB_COVER = 2.5, 0.8  # 元の顔の枠の 2.5 倍を超える枠が、その顔のぼかした楕円の 8 割以上を含む: ぼけた塊を顔と見た物 (隠し済み)


def _center_on(mask: np.ndarray, face: tuple[int, int, int, int]) -> bool:
    x, y, fw, fh = face
    cx, cy = int(x + fw / 2), int(y + fh / 2)
    return 0 <= cy < mask.shape[0] and 0 <= cx < mask.shape[1] and bool(mask[cy, cx])


def head_faces(person_mask: np.ndarray, faces: list[tuple[int, int, int, int]]) -> list[tuple[int, int, int, int]]:
    """枠の中心が人物の形の上にある顔だけを返す。通行人の顔は背景ごと白になるので、ぼかす数に入れない。"""
    return [f for f in faces if _center_on(person_mask, f)]


def recheck(found, faces, step: int, shape) -> tuple[list, list]:
    """確かめの検出 found を (残った顔, 一部だけ楕円にかかる枠) に分ける。単色の段では全部が残った顔。

    ぼかしの段では、この段でぼかした楕円に枠の HIDDEN 以上が入る物は隠し済みとして数えない。
    ぼけた塊の周りを囲む大きな枠 (BLOB_AREA・BLOB_COVER) も隠し済み。足すとぼかしが頭から胸まで広がるため。
    ほかの一部だけかかる物は、元の枠が顔の一部 (手で隠れた・ずれた) だった恐れがあるので、ぼかす所に足してやり直すために返す。"""
    if not faces or step >= len(BLUR):
        return list(found), []
    each = [_ellipses(shape, [f], BLUR[step][1]) for f in faces]
    hidden = np.bitwise_or.reduce(each)
    left, partial = [], []
    for x, y, w, h in found:
        box = (slice(max(0, y), y + h), slice(max(0, x), x + w))
        inside = hidden[box].sum() / (w * h)
        blob = any(w * h > BLOB_AREA * fw * fh and e[box].sum() >= BLOB_COVER * e.sum() for (_, _, fw, fh), e in zip(faces, each))
        if inside < HIDDEN and not blob:
            (partial if inside > 0 else left).append((x, y, w, h))
    return left, partial


def _ellipses(shape, faces, scale) -> np.ndarray:
    m = np.zeros(shape, np.uint8)
    for x, y, fw, fh in faces:  # 画像の外にはみ出した分は cv2 が切る
        cv2.ellipse(m, (round(x + fw / 2), round(y + fh / 2)), (round(fw * scale / 2), round(fh * scale / 2)), 0, 0, 360, 1, -1)
    return m


def head_region(person_mask: np.ndarray, faces: list[tuple[int, int, int, int]]) -> np.ndarray:
    """単色で塗る所 (bool)。人物の形の上の帯の中の人物の形 (全幅。上げた手を頭と取り違えないため) と、顔の枠を広げた楕円。"""
    region = _ellipses(person_mask.shape, faces, FACE_SCALE).astype(bool)
    ys, _ = np.nonzero(person_mask)
    if len(ys):
        top, bottom = ys.min(), ys.max() + 1
        band = top + int((bottom - top) * TOP_BAND)
        region[top:band] |= person_mask[top:band]
    return region


def paint_head(img: np.ndarray, person_mask: np.ndarray, faces: list[tuple[int, int, int, int]]) -> np.ndarray:
    """head_region を灰色で塗った画像を返す。"""
    out = img.copy()
    out[head_region(person_mask, faces)] = GRAY
    return out


def blur_faces(img: np.ndarray, person_mask: np.ndarray, faces, strength: float, scale: float, gray: float) -> tuple[np.ndarray, np.ndarray]:
    """顔ごとに、枠を scale 倍に広げた楕円を強くぼかす (sigma = 顔の高さ × strength)。gray の割合だけ、薄い白黒に寄せる。
    ぼかすのは人物の画素だけ (背景の色は混ぜない)。楕円の中の透過は人物の形を同じ強さでぼかした物にし、横顔の鼻や唇の輪郭を
    人物の縁でくっきり出さない。楕円の縁は外へ向けてなじませる。返り値は (画像 float, 透過 0〜1)。"""
    out = img.astype(np.float32)
    alpha = person_mask.astype(np.float32)
    h, w = img.shape[:2]
    for x, y, fw, fh in faces:
        s = fh * strength
        pad = int(max(fw, fh) * scale / 2 + 3 * s) + 1
        cx, cy = round(x + fw / 2), round(y + fh / 2)
        y0, y1, x0, x1 = max(0, cy - pad), min(h, cy + pad), max(0, cx - pad), min(w, cx + pad)
        if y0 >= y1 or x0 >= x1:
            continue
        crop, m = out[y0:y1, x0:x1], person_mask[y0:y1, x0:x1].astype(np.float32)
        soft = cv2.GaussianBlur(m, (0, 0), s)
        blurred = cv2.GaussianBlur(crop * m[..., None], (0, 0), s) / np.maximum(soft, 1e-3)[..., None]  # 人物の色だけの平均
        blurred = blurred * (1 - gray) + (blurred.mean(2, keepdims=True) / 2 + GRAY / 2) * gray
        e = _ellipses((y1 - y0, x1 - x0), [(x - x0, y - y0, fw, fh)], scale).astype(np.float32)
        f = np.clip(cv2.GaussianBlur(e, (0, 0), fh * 0.05) * 2, 0, 1)  # 楕円の縁で 1、外へ向けて 0 に
        out[y0:y1, x0:x1] = crop * (1 - f[..., None]) + blurred * f[..., None]
        alpha[y0:y1, x0:x1] = alpha[y0:y1, x0:x1] * (1 - f) + soft * f
    return out, alpha


def hide_head(img: np.ndarray, person_mask: np.ndarray, faces: list[tuple[int, int, int, int]], step: int) -> tuple[np.ndarray, np.ndarray]:
    """頭を隠し、背景を白にした画像 (Gemini と SAM に渡す物) と、着姿の透過 (0〜1) を返す。faces は head_faces を通した物。

    顔があれば、step が BLUR の段の内は顔だけをぼかし (髪と頭の形は残す)、次の段で顔の楕円を単色、最後の段で頭の形も単色。
    どの顔も人物の形の上 4 割より下なら、どの段でも頭の形も単色で塗る。
    顔が無ければ (横顔・うつむき・後ろ姿) 頭の形に沿って単色で塗る (step は見ない)。
    透過は人物の形。ぼかしの段だけ、楕円の中を柔らかくする (blur_faces)。
    """
    alpha = person_mask.astype(np.float32)
    if not faces:
        out = paint_head(img, person_mask, [])
    else:
        ys, _ = np.nonzero(person_mask)
        top = ys.min() + (ys.max() + 1 - ys.min()) * FACE_TOP
        head_too = step > len(BLUR) or all(y + fh / 2 >= top for _, y, _, fh in faces)
        if step < len(BLUR):
            out, alpha = blur_faces(img, person_mask, faces, *BLUR[step])
            out = paint_head(out, person_mask, []) if head_too else out
        else:
            out = paint_head(img, person_mask if head_too else np.zeros_like(person_mask), faces)
    a = alpha[..., None]
    return (out * a + 255 * (1 - a)).round().astype(np.uint8), alpha


_DETECT_LOCK = threading.Lock()  # 検出器は大きさの設定を持つので、同時の呼び出しで取り違えないよう 1 つずつ


def find_faces(detector, img: np.ndarray, score: float = 0.6) -> list[tuple[int, int, int, int]]:
    """YuNet (cv2.FaceDetectorYN) で顔の枠 (x, y, w, h) を返す。塗った後の確かめにも使う。"""
    h, w = img.shape[:2]
    with _DETECT_LOCK:
        detector.setInputSize((w, h))
        detector.setScoreThreshold(score)
        _, found = detector.detect(img)
    if found is None:
        return []
    return [tuple(int(v) for v in f[:4]) for f in found]


def largest_blob(alpha: np.ndarray, threshold: int = 128) -> np.ndarray:
    """背景除去の透過 (0〜255) を 2 値にし、一番大きい塊だけを残す。半透明の通行人や柱の影を消すため。"""
    binary = (alpha >= threshold).astype(np.uint8)
    n, labels, stats, _ = cv2.connectedComponentsWithStats(binary, connectivity=8)
    if n <= 1:
        return np.zeros_like(binary, bool)
    biggest = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
    return labels == biggest
