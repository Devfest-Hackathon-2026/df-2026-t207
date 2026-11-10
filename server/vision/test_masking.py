import cv2
import numpy as np
import pytest

from masking import BLUR, STEPS, head_faces, hide_head, largest_blob, paint_head, recheck

GRAY = 128


def _person(h=800, w=600):
    img = np.full((h, w, 3), 255, np.uint8)
    mask = np.zeros((h, w), bool)
    mask[100:700, 200:400] = True  # 人物の形: 縦 600px
    return img, mask


def test_paint_head_paints_top_fifth_of_person():
    img, mask = _person()
    out = paint_head(img, mask, faces=[])
    assert (out[100:220, 200:400] == GRAY).all()  # 上から 600 / 5 = 120px
    assert (out[230:700, 200:400] == 255).all()  # その下は触らない


def test_paint_head_paints_face_as_ellipse_not_box():
    img, mask = _person()
    # 顔の枠 (x, y, w, h) = (250, 300, 40, 40)。2 倍で中心 (270, 320) から半径 40px の円
    out = paint_head(img, mask, faces=[(250, 300, 40, 40)])
    assert (out[320, 234] == GRAY).all()  # 左の端 (36px)
    assert (out[356, 270] == GRAY).all()  # 下の端 (36px)
    assert (out[284, 234] == 255).all()  # 広げた四角の角 (斜め 51px) は塗らない
    assert (out[600, 210] == 255).all()


def test_paint_head_band_paints_whole_width_with_raised_hand():
    img = np.full((800, 600, 3), 255, np.uint8)
    mask = np.zeros((800, 600), bool)
    mask[100:170, 270:330] = True  # 頭 (幅 60px)
    mask[170:700, 150:450] = True  # 肩から下 (幅 300px)
    mask[60:200, 420:440] = True  # 頭の上に上げた手。人物の形は 60〜700 (縦 640px)、帯は 60〜188
    out = paint_head(img, mask, faces=[])
    assert (out[100:170, 270:330] == GRAY).all()  # 頭 (手の幅と取り違えない)
    assert (out[80, 430] == GRAY).all()  # 手
    assert (out[180, 160] == GRAY).all() and (out[180, 300] == GRAY).all()  # 帯の中は人物の全幅
    assert (out[120, 200] == 255).all()  # 帯の中の人物の外 (背景) は塗らない
    assert (out[195:700, 270:330] == 255).all()  # 帯の下は触らない


def _checker(img, y0, y1, x0, x1):
    yy, xx = np.mgrid[y0:y1, x0:x1]
    img[y0:y1, x0:x1] = (((yy // 4 + xx // 4) % 2) * 255)[..., None]  # 4px の市松 (顔の細部の代わり)


FACE = (270, 130, 60, 70)  # 帯 (100〜220) の中の顔の枠 (x, y, w, h)。中心 (300, 165)


def test_head_faces_drops_faces_off_the_person():
    _, mask = _person()
    low = (280, 400, 40, 40)  # 人物の上の低い所 (うつむき・寄りの写真の顔、または服の柄の顔)。どちらもぼかす側に入れる
    passerby = (500, 120, 40, 40)  # 人物の形の外の通行人 (背景ごと白になる)
    assert head_faces(mask, [FACE, low, passerby]) == [FACE, low]


def test_blur_hides_face_but_keeps_hair_and_band():
    img, mask = _person()
    _checker(img, 100, 700, 200, 400)
    out, _ = hide_head(img, mask, [FACE], step=0)
    assert out[155:175, 290:310].astype(float).std() < 20  # 顔の真ん中は細部が残らない
    assert (out[100:105, 200:400] == img[100:105, 200:400]).all()  # 頭のてっぺん (髪) は元のまま
    assert (out[300:700] == img[300:700]).all()  # 帯は塗らない、顔の外は元のまま


def test_blur_gets_stronger_each_step():
    img, mask = _person()
    yy = np.mgrid[0:800, 0:600][0]
    img[:] = (np.sin(yy / 6) * 100 + 128).astype(np.uint8)[..., None]  # 顔の高さに数本の縞
    spread = [hide_head(img, mask, [FACE], step=s)[0][145:185, 290:310].astype(float).std() for s in range(len(BLUR))]
    assert spread == sorted(spread, reverse=True) and spread[0] > spread[-1]


def test_after_blur_steps_paints_face_ellipse_then_whole_head():
    img, mask = _person()
    face, _ = hide_head(img, mask, [FACE], step=len(BLUR))
    assert (face[165, 300] == GRAY).all()
    assert (face[105, 205] == 255).all() and (face[600, 300] == 255).all()  # 楕円の外の帯は塗らない
    head, _ = hide_head(img, mask, [FACE], step=len(BLUR) + 1)  # 最後の段: 頭の形 + 顔の楕円 (顔の外の頭が顔と見られた時)
    assert (head[105, 205] == GRAY).all() and (head[165, 300] == GRAY).all()
    assert STEPS == len(BLUR) + 2


def test_recheck_sorts_detections_by_overlap_with_own_blur():
    shape = (800, 600)
    # 1 段目の楕円は中心 (300, 165)、半径 横 37.5 縦 43.75
    inside = (285, 145, 30, 40)  # 全部が楕円の中: 隠し済み
    outside = (280, 400, 40, 40)  # 楕円にかからない: 残った顔として次の段へ
    big = (200, 60, 120, 120)  # 一部だけかかる (元の枠が顔の一部だった恐れ): ぼかす所に足してやり直す
    assert recheck([inside, outside, big], [FACE], 0, shape) == ([outside], [big])
    assert recheck([inside, outside, big], [FACE], len(BLUR), shape) == ([inside, outside, big], [])  # 単色の段では全部数える
    assert recheck([inside], [], 0, shape) == ([inside], [])


def test_recheck_treats_box_around_own_blur_as_hidden():
    shape = (800, 600)
    # 元の顔の枠 60x70 (面積 4200)。1 段目の楕円は x 262〜338、y 121〜209
    blob = (250, 110, 100, 110)  # 面積 11000 (2.5 倍の 10500 を超える) で、楕円を丸ごと含む: ぼけた塊を顔と見た物
    small = (255, 115, 90, 100)  # 楕円を含むが面積 9000 (2.5 倍以下): 顔の一部だった恐れとしてやり直す
    shifted = (200, 60, 120, 120)  # 大きいが楕円の 8 割を含まない: やり直す
    assert recheck([blob, small, shifted], [FACE], 0, shape) == ([], [small, shifted])


def test_face_low_on_person_also_paints_head():
    img, mask = _person()
    img[:] = (200, 150, 120)
    low = (270, 380, 60, 70)  # 中心の高さ 415 は人物の形 (100〜700) の上 4 割 (340) より下。服の柄の顔かもしれない
    out, _ = hide_head(img, mask, [low], step=0)
    assert (out[105, 205] == GRAY).all()  # 頭の形も塗る
    assert not (out[415, 300] == GRAY).all()  # 顔はぼかし
    assert (hide_head(img, mask, [FACE], step=0)[0][105, 205] == (200, 150, 120)).all()  # 上の顔なら頭は塗らない


def test_blur_softens_person_edge_only_inside_ellipse_without_background():
    img, mask = _person()
    img[:] = 90  # 背景
    img[mask] = (200, 150, 120)  # 人物
    edge = (370, 130, 60, 70)  # 中心 (400, 165)、人物の形 (x 200〜400) の右の縁 (横顔の鼻先)
    clean, alpha = hide_head(img, mask, [edge], 0)
    assert 0 < alpha[165, 405] < 1 and 0 < alpha[165, 395] < 1  # 楕円の中は柔らかい透過
    assert alpha[400, 405] == 0 and alpha[400, 395] == 1  # 楕円の外は人物の形のまま
    assert abs(clean[165, 398].astype(int) - clean[165, 402]).max() < 40  # 縁の内外で段差が無い
    assert (clean[165, 405] >= (198, 148, 118)).all() and not (clean[165, 405] == 255).all()  # 背景の色は混ぜず、白とだけ混ぜる
    assert (clean[400, 405] == 255).all()  # 楕円の外の人物の外は白
    assert (hide_head(img, mask, [edge], len(BLUR))[1] == mask).all()  # 単色の段は人物の形のまま


def test_no_face_paints_head_shape_solid():
    img, mask = _person()
    assert (hide_head(img, mask, [], step=0)[0][100:220, 200:400] == GRAY).all()


def test_largest_blob_keeps_only_biggest_solid_region():
    alpha = np.zeros((100, 100), np.uint8)
    alpha[10:60, 10:60] = 255  # 本人
    alpha[80:90, 80:90] = 255  # 小さい塊 (隣の人の端など)
    alpha[10:60, 70:95] = 60  # 半透明 (柱や通行人の影)
    m = largest_blob(alpha)
    assert m[30, 30]
    assert not m[85, 85]
    assert not m[30, 80]


import os

YUNET = os.path.expandvars(r"%LOCALAPPDATA%\df-hack26\models\yunet.onnx")
FACE_IMG = os.path.expandvars(r"%LOCALAPPDATA%\df-hack26\seg-bench\imgs\c9.jpg")
FACE_MASK = os.path.expandvars(r"%LOCALAPPDATA%\df-hack26\seg-bench\out\_mask_c9.png")  # isnet の人物の形 (headpaint.py が作る)
need_local = pytest.mark.skipif(not all(map(os.path.exists, (YUNET, FACE_IMG, FACE_MASK))), reason="手元の YuNet と試験の写真が要る")


@need_local
def test_real_face_passes_in_first_blur_step():
    from pipeline import REDO, process

    class Counting:  # 本物の YuNet の detect の回数を数える
        def __init__(self):
            self.det, self.calls = cv2.FaceDetectorYN.create(YUNET, "", (320, 320)), 0

        def __getattr__(self, name):
            return getattr(self.det, name)

        def detect(self, img):
            self.calls += 1
            return self.det.detect(img)

    det = Counting()
    mask = cv2.imread(FACE_MASK, cv2.IMREAD_GRAYSCALE)
    rgb = cv2.cvtColor(cv2.imread(FACE_IMG), cv2.COLOR_BGR2RGB)
    process(rgb, remove_bg=lambda im: mask, detector=det, ask_gemini=lambda im: [], sam=None, sam_embed=lambda im: None)
    assert det.calls <= 1 + REDO + 1  # 塗る前の 1 回と、色のままのぼかし (段 1) のやり直しまでで通る


def test_paint_head_ignores_face_box_fully_outside_frame():
    img, mask = _person()
    out = paint_head(img, np.zeros_like(mask), faces=[(100, -60, 20, 20)])  # 枠全体が画像の上にはみ出す
    assert (out == 255).all()

