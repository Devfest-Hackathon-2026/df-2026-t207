"""デモの照合と着用イメージを事前に作る (tasks の D3)。api と同じ照合の手順 (match.run_match) を使う。

見る人 (viewer) が見られる側 (owners) の今の着姿の服を 1 着ずつ見たとして照合し、
precomputed/match_{viewer}_{owner}_{itemId} に置く。照合が返した組み合わせごとに着用イメージを作り、
precomputed/tryon_{viewer}_{owner}_{itemId}_{手持ちの id を並べ替えて _ でつないだ物} に置く。

使い方 (df-hack26 で、seg-bench の venv):
    python scripts/precompute_demo.py --viewer demo-viewer --owners demo-aki,demo-ren
    壇上の本人の分: --viewer <B の uid> --owners <A の uid>
"""
import argparse
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "server" / "api"))

from match import run_match  # noqa: E402
from nearby import _outfit  # noqa: E402


def precompute(db, blobs, viewer: str, owners: list[str], ask, make) -> dict:
    photo = blobs.get(f"users/{viewer}/photo.jpg")
    if photo is None:
        raise SystemExit(f"{viewer} の全身写真がありません (seed_demo を先に)")
    jobs, n = [], {"match": 0, "tryon": 0}
    for owner in owners:
        _, outfit = _outfit(db, owner, None, True)  # 一番新しい日付の着姿
        for wid in (outfit or {}).get("items", []):
            item = db.document(f"users/{owner}/wardrobeItems/{wid}").get().to_dict()
            seen_png = blobs.get(item.get("image", "")) if item else None
            if seen_png is None:
                continue
            out = run_match(db, blobs, viewer, item, seen_png, ask)
            db.document(f"precomputed/match_{viewer}_{owner}_{wid}").set(out)
            n["match"] += 1
            print(f"{owner} {item.get('label')}: 組み合わせ {len(out['combos'])}、足りない {bool(out['missing'])}、似た服 {bool(out['similarOwned'])}")
            for combo in out["combos"]:
                ids = sorted(combo["wardrobeItemIds"])
                mine = [db.document(f"users/{viewer}/wardrobeItems/{i}").get().to_dict() for i in ids]
                jobs.append((f"{viewer}_{owner}_{wid}_" + "_".join(ids), [seen_png, *[blobs.get(m["image"]) for m in mine]]))

    for key, garments in jobs:  # 画像の生成は 1 分あたりの上限が低い (4 本並べて 429 になった) ので 1 本ずつ
        if db.document(f"precomputed/tryon_{key}").get().exists:
            continue  # 作り直しの時に、作った物は飛ばす
        for wait in (0, 15, 30, 60, 120):
            time.sleep(wait)
            try:
                png = make(photo, garments)
                break
            except Exception as e:
                if "429" not in str(e) or wait == 120:
                    raise
                print(f"  429。{wait * 2 or 15} 秒待ってやり直す")
        path = f"precomputed/{key}.png"
        blobs.put(path, png)
        db.document(f"precomputed/tryon_{key}").set({"image": path})
        n["tryon"] += 1
    return n


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--viewer", required=True)
    ap.add_argument("--owners", required=True)
    a = ap.parse_args()
    os.environ.setdefault("GOOGLE_CLOUD_PROJECT", "project-10522535-9db8-40c0-a68")
    from google.cloud import firestore

    import ai
    from blobs import get_blobs

    print(precompute(firestore.Client(), get_blobs(), a.viewer, a.owners.split(","), ai.ask_match, ai.make_tryon))
