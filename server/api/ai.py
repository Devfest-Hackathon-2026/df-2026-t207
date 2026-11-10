"""Gemini の呼び出し (照合と着用イメージ)。自動のテストは偽物に替える (本物を呼ぶ試験は無い)。

AI_DISABLED=1 の時はどちらも AiDisabled を投げる (S6)。
"""
import io
import json
import os
import threading
from functools import lru_cache
from typing import Literal

from pydantic import BaseModel

MATCH_MODEL = "gemini-3.8-flash"
EMBED_MODEL = "gemini-embedding-2"
# 画像の生成はモデルごとに 1 分 2 回まで (調整できない上限、2026-11-08 に割り当ての画面で確認)。1 つ目が 429 なら 2 つ目で作る
TRYON_MODELS = ("gemini-nano-banana-2.1", "gemini-3-pro-image")
Slot = Literal["outer", "top", "bottom", "dress", "shoes", "bag", "accessory"]


class AiDisabled(Exception):
    pass


def _check():
    if os.environ.get("AI_DISABLED") == "1":
        raise AiDisabled()


_CLIENT_LOCK = threading.Lock()


def _client():
    """Client は 1 つだけ。並べた初回の呼び出しで何個も作ると、捨てられた方が閉じて、送りかけの要求が RuntimeError で落ちる"""
    with _CLIENT_LOCK:
        return _new_client()


@lru_cache
def _new_client():
    from google import genai

    return genai.Client(vertexai=True, project=os.environ.get("GOOGLE_CLOUD_PROJECT", "project-10522535-9db8-40c0-a68"), location="global")


class Combo(BaseModel):
    wardrobeItemIds: list[str]
    reason: str


class Missing(BaseModel):
    slot: Slot
    description: str


class Similar(BaseModel):
    wardrobeItemId: str
    reason: str


class MatchOut(BaseModel):
    combos: list[Combo]
    missing: Missing | None
    similarOwned: Similar | None


MATCH_PROMPT = """あなたはスタイリストです。最初の画像は、街で見かけた人の服 1 着 (見た服) です。続く画像は、利用者の手持ちの服で、それぞれ直前に id を書いています。
見た服を買ったとして、手持ちとどう組み合わせると良いかを考えてください。
色・スタイル・場面・季節・素材・バランスの 6 観点で採点し、良い順に返します。
- combos: 見た服と一緒に着る手持ちの組み合わせを 3 つまで。1 つの組み合わせは手持ち 1〜3 着。wardrobeItemIds には上の id だけを書く (見た服は含めない)。見た服と同じ役割の服 (見た服が上着なら手持ちの上着) は入れない。reason は日本語で 1〜2 文
- missing: 合う組み合わせが無い時だけ、足りない 1 着 (slot と日本語の description、例 白の無地のスニーカー)。合う物があれば null
- similarOwned: 見た服とよく似た服 (同じ役割で、色・形・素材が近く、買わなくても代わりになる物) を手持ちにもう持っていれば、その id と理由。無ければ null"""


def ask_match(seen: dict, seen_png: bytes, candidates: list[tuple[str, dict, bytes]]) -> dict:
    """見た服と手持ち (id, 服の情報, 切り抜きの PNG) を見せ、MatchResult の combos・missing・similarOwned を返す。"""
    _check()
    from google.genai import types

    png = lambda b: types.Part.from_bytes(data=b, mime_type="image/png")  # noqa: E731
    contents = [MATCH_PROMPT, "見た服: " + json.dumps(seen, ensure_ascii=False), png(seen_png)]
    for wid, g, b in candidates:
        contents += [f"id: {wid} " + json.dumps(g, ensure_ascii=False), png(b)]
    r = _client().models.generate_content(
        model=MATCH_MODEL,
        contents=contents,
        config=types.GenerateContentConfig(temperature=0.2, response_mime_type="application/json", response_schema=MatchOut),
    )
    if r.parsed is None:
        raise ValueError("Gemini の応答が形に合わない")
    return r.parsed.model_dump()


def embed(png: bytes) -> list[float]:
    """服の切り抜きを 1536 次元のベクトルにする (同じ服の判定、docs/architecture.md の 3.6)。"""
    _check()
    from google.genai import types

    r = _client().models.embed_content(model=EMBED_MODEL, contents=[types.Part.from_bytes(data=_on_white(png), mime_type="image/jpeg")],
                                       config=types.EmbedContentConfig(output_dimensionality=1536))
    return list(r.embeddings[0].values)


class SameOut(BaseModel):
    wardrobeItemId: str | None
    reason: str


SAME_PROMPT = """最初の画像は、利用者が今日着ている服 1 着です。続く画像は利用者の手持ちの服で、それぞれ直前に id を書いています。
今日の服と同じ 1 着 (同じ物を別の日に撮った物) が手持ちにあれば、その id と理由 (日本語で 1 文) を返してください。
色・柄・形・素材・ロゴなどの細部まで同じと言える時だけ選びます。似ているだけの別の服なら wardrobeItemId は null にします。"""


def pick_same(item: dict, png: bytes, candidates: list[tuple[str, dict, bytes]]) -> dict | None:
    """今日の服と同じ手持ちを 1 着選ばせる。どれでもなければ None。"""
    _check()
    from google.genai import types

    part = lambda b: types.Part.from_bytes(data=b, mime_type="image/png")  # noqa: E731
    contents = [SAME_PROMPT, "今日の服: " + json.dumps(item, ensure_ascii=False), part(png)]
    for wid, g, b in candidates:
        contents += [f"id: {wid} " + json.dumps(g, ensure_ascii=False), part(b)]
    r = _client().models.generate_content(
        model=MATCH_MODEL, contents=contents,
        config=types.GenerateContentConfig(temperature=0.1, response_mime_type="application/json", response_schema=SameOut),
    )
    if r.parsed is None:
        raise ValueError("Gemini の応答が形に合わない")
    return r.parsed.model_dump() if r.parsed.wardrobeItemId else None


def _on_white(b: bytes) -> bytes:
    """透過 PNG の切り抜きを白地の JPEG にする (透明が黒く読まれるのを避ける)。"""
    from PIL import Image

    im = Image.open(io.BytesIO(b)).convert("RGBA")
    out = Image.new("RGB", im.size, (255, 255, 255))
    out.paste(im, (0, 0), im)
    buf = io.BytesIO()
    out.save(buf, "JPEG", quality=90)
    return buf.getvalue()


def make_tryon(photo: bytes, garments: list[bytes]) -> bytes:
    """本人の全身写真 (JPEG) に、切り抜き (透過 PNG、1 枚目が見た服) を着せた PNG を返す。"""
    _check()
    from google.genai import types
    from PIL import Image

    n = len(garments)
    prompt = (f"Image 1 is a photo of a person. Images 2 to {n + 1} are clothing items. "
              "Dress the person in image 1 with all of these items, replacing what they currently wear in the same body area. "
              "Keep the person's face, hair, pose, body shape and background unchanged. "
              "Keep each garment's color, texture and details faithful to its image. "
              "Output one photorealistic full-body image with the same framing as image 1.")
    parts = [types.Part.from_bytes(data=photo, mime_type="image/jpeg")]
    parts += [types.Part.from_bytes(data=_on_white(g), mime_type="image/jpeg") for g in garments]
    for model in TRYON_MODELS:
        try:
            r = _client().models.generate_content(
                model=model, contents=[*parts, prompt], config=types.GenerateContentConfig(response_modalities=["IMAGE"])
            )
            break
        except Exception as e:
            if not any(code in str(e) for code in ("429", "503")) or model == TRYON_MODELS[-1]:  # 混んでいれば予備のモデルへ
                raise
    for part in r.candidates[0].content.parts:
        if part.inline_data:
            return label_ai(part.inline_data.data)
    raise ValueError("着用イメージが返らなかった")


def label_ai(data: bytes) -> bytes:
    """下の帯に「AI-generated」を焼き込んだ PNG にする。画面の外に持ち出されても AI の画像と分かるように。
    ponytail: コンテナに日本語のフォントが無いので英字。日本語の表示はアプリが TryOn.label を出す"""
    from PIL import Image, ImageDraw, ImageFont

    im = Image.open(io.BytesIO(data)).convert("RGB")
    size = max(14, im.width // 24)
    draw = ImageDraw.Draw(im)
    draw.rectangle((0, im.height - size * 2, im.width, im.height), fill=(0, 0, 0))
    draw.text((size // 2, im.height - size * 3 // 2), "AI-generated", fill=(255, 255, 255), font=ImageFont.load_default(size=size))
    buf = io.BytesIO()
    im.save(buf, "PNG")
    return buf.getvalue()
