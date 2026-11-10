"""ビルドの時の確かめ (Dockerfile から流す)。間引いた transformers と入れた重みで、実際の処理の道を一通り通す。

壊れていればビルドが落ちる。通す物: 背景を消す (rembg)、顔を探す (YuNet)、SAM の画像の読み込みと、点と枠を渡す切り抜き。
rembg の import が遅ければ、numba の翻訳がまた起動のたびに走っている (NUMBA_CPU_NAME が効いていない) ので落とす。
"""
import main  # rembg・transformers より先に読む (load_local の中で import の秒数を測るため)

main.load_local()
import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402
from rembg import remove  # noqa: E402

from masking import find_faces  # noqa: E402
from models import sam_embed, sam_masks  # noqa: E402

assert main.LOAD["importRembg"] < 15, f"rembg の import が遅い ({main.LOAD['importRembg']} 秒)。numba のキャッシュが効いていない"
img = np.full((256, 192, 3), 200, np.uint8)
remove(Image.fromarray(img), session=main.M["isnet"], only_mask=True)
find_faces(main.M["yunet"], img)
items = [  # 互いの点が枠に入る 2 着 (含める点と除く点の両方を通す)
    {"box_2d": [100, 100, 900, 900], "points": [[300, 500]]},
    {"box_2d": [200, 200, 800, 800], "points": [[600, 500]]},
]
emb = sam_embed(main.M["sam_proc"], main.M["sam"], img)
masks = sam_masks(main.M["sam_proc"], main.M["sam"], img, items, emb)
assert len(masks) == 2 and masks[0].shape == img.shape[:2]
print("selfcheck ok", main.LOAD, flush=True)
