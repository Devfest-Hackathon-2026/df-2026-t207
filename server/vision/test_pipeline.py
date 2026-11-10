import cv2
import numpy as np
import pytest

from masking import BLUR
from pipeline import ProcessError, process


FACE_BOX = [250, 120, 40, 40]  # 帯の中の顔
ELSEWHERE = [250, 500, 40, 40]  # 顔の楕円の外 (人物の形の中)


class FakeDetector:
    """cv2.FaceDetectorYN の代わり。face_on に入れた回目の detect だけ顔を返す (1 回目 = 塗る前)。
    2 回目からの確かめでは recheck の枠を返す (既定は顔と同じ所 = ぼかした楕円の中)。"""

    def __init__(self, face_on=(), recheck=None, box=FACE_BOX):
        self.face_on, self.box, self.calls, self.sizes, self.scores = set(face_on), box, 0, [], []
        self.recheck = recheck or box

    def setInputSize(self, size):
        self.sizes.append(size)

    def setScoreThreshold(self, s):
        self.scores.append(s)

    def detect(self, img):
        self.calls += 1
        if self.calls in self.face_on:
            return 1, np.array([(self.box if self.calls == 1 else self.recheck) + [0] * 10 + [0.9]], np.float32)
        return 1, None


def person_alpha(img):
    a = np.zeros(img.shape[:2], np.uint8)
    h, w = a.shape
    a[h // 8 : h * 7 // 8, w // 3 : w * 2 // 3] = 255  # 人物の形
    return a


ITEMS = [
    {"slot": "outer", "category": "jacket", "label": "ジャケット", "layer": "outer", "color": "紺",
     "box_2d": [200, 300, 600, 700], "points": [[300, 350], [400, 650]]},
    {"slot": "top", "category": "sweater", "label": "ニット", "layer": "inner", "color": "赤",
     "box_2d": [250, 400, 550, 600], "points": [[400, 500]]},
]


def fake_sam(img, items, emb):
    out = []
    h, w = img.shape[:2]
    for it in items:
        y0, x0, y1, x1 = it["box_2d"]
        m = np.zeros((h, w), bool)
        m[y0 * h // 1000 : y1 * h // 1000, x0 * w // 1000 : x1 * w // 1000] = True
        out.append(m)
    return out


def run(img=None, detector=None, items=ITEMS, **kw):
    img = np.full((800, 600, 3), 200, np.uint8) if img is None else img
    calls = {"gemini": [], "sam": []}

    def ask(x):
        calls["gemini"].append(x)
        return items

    def sam(x, its, emb):
        calls["sam"].append((x, its))
        return fake_sam(x, its, emb)

    args = dict(remove_bg=person_alpha, detector=detector or FakeDetector(), ask_gemini=ask, sam=sam, sam_embed=lambda x: None)
    args.update(kw)
    return process(img, **args), calls


def test_face_left_after_every_step_stops_before_gemini():
    called = []
    with pytest.raises(ProcessError) as e:  # 塗る前も、ぼかしの全部の段と単色の後も顔がある
        process(np.full((800, 600, 3), 200, np.uint8), remove_bg=person_alpha, detector=FakeDetector(face_on=range(1, 20), recheck=ELSEWHERE),
                ask_gemini=lambda x: called.append(x) or ITEMS, sam=fake_sam, sam_embed=lambda x: called.append(x))
    assert e.value.code == "face_detected"
    assert called == []  # Gemini も SAM も呼ばない


def test_no_person_stops():
    with pytest.raises(ProcessError) as e:
        run(remove_bg=lambda img: np.zeros(img.shape[:2], np.uint8))
    assert e.value.code == "no_person"


def test_zero_items_succeeds_with_empty_list():
    res, _ = run(items=[])
    assert res["items"] == []
    assert res["outfitImage"].startswith(b"\x89PNG")


def test_points_out_of_range_are_clipped():
    bad = [dict(ITEMS[0], box_2d=[-50, 300, 1400, 1200], points=[[1200, -10], [500, 500]])]
    res, calls = run(items=bad)
    sent = calls["sam"][0][1][0]
    assert sent["box_2d"] == [0, 300, 1000, 1000]
    assert sent["points"] == [[1000, 0], [500, 500]]
    assert res["items"][0]["points"] == [{"y": 1000, "x": 0}, {"y": 500, "x": 500}]  # Firestore は配列の中の配列を持てない


def test_large_image_is_resized_to_2048():
    res, calls = run(img=np.full((4000, 3000, 3), 200, np.uint8))
    assert calls["gemini"][0].shape[:2] == (2048, 1536)
    out = cv2.imdecode(np.frombuffer(res["outfitImage"], np.uint8), cv2.IMREAD_UNCHANGED)
    assert out.shape == (2048, 1536, 4)


def test_result_has_one_png_per_item():
    res, _ = run()
    assert [it["index"] for it in res["items"]] == [0, 1]
    assert all(it["image"].startswith(b"\x89PNG") for it in res["items"])
    assert res["items"][1]["label"] == "ニット"
    assert "box_2d" not in res["items"][0]  # Job の形に無い物は返さない


def test_gemini_gets_painted_head_and_white_background():
    res, calls = run()
    sent = calls["gemini"][0]
    assert (sent[0, 0] == 255).all()  # 背景は白
    assert (sent[110, 300] == 128).all()  # 人物の形の上の帯は灰色


def test_face_left_after_blur_retries_stronger():
    det = FakeDetector(face_on={1, 2}, recheck=ELSEWHERE)  # 1 = 塗る前、2 = 1 段目のぼかしの後 (楕円の外に顔)
    res, calls = run(detector=det)
    assert det.calls == 3  # 2 段目で通る
    assert len(calls["gemini"]) == 1


def test_face_left_after_all_blur_falls_back_to_solid():
    det = FakeDetector(face_on=range(1, len(BLUR) + 2), recheck=ELSEWHERE)  # 塗る前とぼかしの全部の段
    res, calls = run(detector=det)
    assert det.calls == len(BLUR) + 2
    assert (calls["gemini"][0][140, 270] == 128).all()  # 顔の所は単色


def test_detection_inside_own_blur_counts_as_hidden():
    det = FakeDetector(face_on={1, 2})  # 確かめの検出は、自分でぼかした楕円の中
    res, calls = run(detector=det)
    assert det.calls == 2  # 段 1 で通る
    assert not (calls["gemini"][0][140, 270] == 128).all()  # 単色ではなくぼかし


def test_profile_edge_inside_blur_is_not_cut_by_person_shape():
    img = np.full((800, 600, 3), 90, np.uint8)  # 背景
    img[100:700, 200:400] = (200, 150, 120)  # 人物 (person_alpha と同じ所)。顔の右半分は人物の形の外 (横顔の鼻先の外)
    res, calls = run(img=img, detector=FakeDetector(face_on={1}, box=[370, 120, 40, 60]))  # 中心 (390, 150)、縁は x=400
    sent = calls["gemini"][0].astype(int)
    assert abs(sent[150, 398] - sent[150, 402]).max() < 40  # 縁の内外で段差が無い (前は 255 の白で切れていた)
    assert (sent[150, 405] >= (198, 148, 118)).all() and not (sent[150, 405] == 255).all()  # 人物の色を白と混ぜる。背景 (90) は混ぜない
    assert (sent[150, 440] == 255).all()  # 楕円の外は白
    outfit = cv2.imdecode(np.frombuffer(res["outfitImage"], np.uint8), cv2.IMREAD_UNCHANGED)
    assert 0 < outfit[150, 405, 3] < 255 and outfit[150, 440, 3] == 0  # 透過は楕円の中だけ柔らかい


def test_partial_overlap_widens_blur_and_redoes_same_step():
    det = FakeDetector(face_on=range(1, 30), recheck=[262, 95, 80, 80])  # 元の枠 (顔の一部) の楕円に一部だけかかり、楕円の 8 割は含まない、ずれた広い枠
    res, calls = run(detector=det)
    assert det.calls == 3  # 1 段目をやり直し、広げた楕円に 9 割以上入って通る
    assert len(calls["gemini"]) == 1


def test_partial_overlap_redoes_at_most_twice_per_step():
    det = FakeDetector(face_on=range(1, 50), recheck=[-100, 150, 400, 100])  # 半分が画像の外で、楕円に 9 割は入らず、楕円の下の方しか含まない
    with pytest.raises(ProcessError) as e:
        run(detector=det)
    assert e.value.code == "face_detected"
    assert det.calls == 1 + 3 * len(BLUR) + 2  # ぼかしの段は 3 回ずつ、単色の 2 段は 1 回ずつ


def test_face_found_is_blurred_and_band_is_not_painted():
    img = np.full((800, 600, 3), 200, np.uint8)
    img[100:110, 300:400] = (30, 20, 10)  # 頭のてっぺん (髪)。顔の楕円の外
    res, calls = run(img=img, detector=FakeDetector(face_on={1}))
    sent = calls["gemini"][0]
    assert (sent[105, 350] == (30, 20, 10)).all()  # 髪は残す
    assert not (sent[110:220, 200:400] == 128).all(axis=-1).any()  # 灰色の帯は無い


def test_face_left_after_face_solid_paints_whole_head():
    det = FakeDetector(face_on=range(1, len(BLUR) + 3), recheck=ELSEWHERE)  # 顔の楕円を塗った後も残る (隣の人の後ろ頭など)
    res, calls = run(detector=det)
    assert det.calls == len(BLUR) + 3
    assert (calls["gemini"][0][105, 205] == 128).all()  # 頭の形の帯も塗る


def test_gemini_error_is_ai_failed():
    def boom(x):
        raise RuntimeError("bad json")

    with pytest.raises(ProcessError) as e:
        run(ask_gemini=boom)
    assert e.value.code == "ai_failed"


def test_reports_statuses_in_order():
    seen = []
    run(on_status=lambda s, p: seen.append(s))
    assert seen == ["masking", "segmenting", "detecting", "cutting"]


@pytest.mark.parametrize("box", [[100, 200, 300], [], [1, 2, 3, 4, 5]])
def test_malformed_box_is_dropped(box):
    res, _ = run(items=[dict(ITEMS[0], box_2d=box), ITEMS[1]])
    assert [it["label"] for it in res["items"]] == ["ニット"]


def test_recheck_after_painting_is_stricter():
    det = FakeDetector()
    run(detector=det)
    assert det.scores[1] <= 0.3 < det.scores[0]  # 安全網なので、塗った後は見落としより誤検出に倒す


def test_empty_required_field_is_kept():
    res, _ = run(items=[dict(ITEMS[1], color="")])
    assert res["items"][0]["color"] == ""
