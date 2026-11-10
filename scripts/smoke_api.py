"""配備した api を、Web デモの審査員と同じ流れで通しで試す (匿名ログイン → 模擬の検出 → カードの画像 → 照合 → 着用イメージ)。

使い方 (df-hack26 で、seg-bench の venv):
    python scripts/smoke_api.py [api の URL]   既定は普段の URL (審査員が使う物)
試すたびに Firebase に匿名の利用者が 1 人増える (30 日で自動で消える)。鍵とトークンは表示しない。
"""
import json
import shutil
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

# PATH の gcloud。無ければ Windows の既定の入れ場所
G = shutil.which("gcloud") or str(Path.home() / "AppData/Local/Google/Cloud SDK/google-cloud-sdk/bin/gcloud.cmd")
P = "project-10522535-9db8-40c0-a68"
API = sys.argv[1] if len(sys.argv) > 1 else "https://api-591807217114.asia-northeast1.run.app"


def anon_token() -> str:
    keys = subprocess.run([G, "services", "api-keys", "list", f"--project={P}", "--format=value(uid,displayName)"],
                          capture_output=True, text=True).stdout.splitlines()
    uid = next(line.split()[0] for line in keys if "Browser key" in line)
    key = subprocess.run([G, "services", "api-keys", "get-key-string", uid, f"--project={P}", "--format=value(keyString)"],
                         capture_output=True, text=True).stdout.strip()
    req = urllib.request.Request(f"https://identitytoolkit.googleapis.com/v1/accounts:signUp?key={key}",
                                 data=b'{"returnSecureToken":true}',
                                 # ブラウザ用のキーは Hosting からの呼び出しだけを通す (2026-11-09 に制限を入れた)
                                 headers={"Content-Type": "application/json", "Referer": "https://project-10522535-9db8-40c0-a68.web.app/"})
    return json.load(urllib.request.urlopen(req))["idToken"]


TOKEN = anon_token()


def call(method: str, path: str, body: dict | None = None):
    h = {"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json"}
    t = time.time()
    try:
        r = urllib.request.urlopen(urllib.request.Request(API + path, data=json.dumps(body).encode() if body else None,
                                                          headers=h, method=method), timeout=120)
        data, ct = r.read(), r.headers.get("content-type", "")
        return r.status, round(time.time() - t, 1), json.loads(data) if "json" in ct else f"{ct} {len(data)}B"
    except urllib.error.HTTPError as e:
        return e.code, round(time.time() - t, 1), e.read().decode("utf-8", "replace")[:150]


def check(name: str, ok: bool, detail) -> None:
    print(f"{'OK ' if ok else 'NG '} {name}: {detail}")
    if not ok:
        sys.exit(1)


# 審査員の最初の画面 (ホームとマイページ): Demo として、今日のコーデを公開中に見える
s, sec, me = call("GET", "/v1/me")
check("自分 (Demo)", s == 200 and me["publishing"]["visibility"] == "nearby", f"{s} {sec}s {me.get('displayName') if s == 200 else me} 公開 {me['publishing'] if s == 200 else ''}")
s, sec, today = call("GET", "/v1/outfits/today")
check("今日のコーデ", s == 200 and today["items"], f"{s} {sec}s {today.get('date') if s == 200 else today} 服 {len(today.get('items', [])) if s == 200 else ''}")
s, sec, img = call("GET", "/v1/outfits/today/image")
check("今日のコーデの画像", s == 200 and "png" in str(img), f"{s} {sec}s {img}")
s, sec, near = call("POST", "/v1/demo/nearby")
check("模擬の検出", s == 200 and near["cards"], f"{s} {sec}s カード {len(near['cards']) if s == 200 else near}")
card = near["cards"][0]
item = card["items"][0]
s, sec, img = call("GET", card["image"])
check("カードの着姿", s == 200 and "png" in str(img), f"{s} {sec}s {img}")
s, sec, img = call("GET", item["image"])
check("カードの服", s == 200 and "png" in str(img), f"{s} {sec}s {img}")
s, sec, m = call("POST", "/v1/match", {"cardId": card["cardId"], "cardItemId": item["cardItemId"]})
check("照合", s == 200 and m["combos"], f"{s} {sec}s 事前 {m.get('precomputed') if s == 200 else m} 組み合わせ {len(m.get('combos', [])) if s == 200 else ''}")
ids = m["combos"][0]["wardrobeItemIds"]
s, sec, t = call("POST", "/v1/tryon", {"cardId": card["cardId"], "cardItemId": item["cardItemId"], "wardrobeItemIds": ids})
check("着用イメージ", s == 200, f"{s} {sec}s 事前 {t.get('precomputed') if s == 200 else t}")
s, sec, img = call("GET", t["image"])
check("着用イメージの画像", s == 200 and "png" in str(img), f"{s} {sec}s {img}")
s, sec, w = call("GET", "/v1/wardrobe")
check("手持ち (デモの見る人)", s == 200, f"{s} {sec}s {len(w['items']) if s == 200 else w} 着")
