#!/usr/bin/env bash
# Web デモを Firebase Hosting に公開する (W3)。
# 先に一度だけ `firebase login` しておく。
#   ./scripts/deploy_web.sh
# api の住所を替える時: API_BASE_URL=https://... ./scripts/deploy_web.sh
set -euo pipefail
cd "$(dirname "$0")/.."

API_BASE_URL="${API_BASE_URL:-https://api-591807217114.asia-northeast1.run.app}"

(cd app && flutter build web --release --dart-define=API_BASE_URL="$API_BASE_URL")
# 審査員向けの APK (/wear-by.apk) は build/web に無いので、出し直すと消える。
# 作り直した APK を出す時は APK_FILE=<path> を渡す。渡さず置き場にも無ければ、今公開中の物を取ってくる (途中で切れても残らないよう別名で受けてから置く)
APK=app/build/web/wear-by.apk
if [ -n "${APK_FILE:-}" ]; then
  cp "$APK_FILE" "$APK"
elif [ ! -f "$APK" ]; then
  curl -fsSL https://project-10522535-9db8-40c0-a68.web.app/wear-by.apk -o "$APK.part" && mv "$APK.part" "$APK"
fi
# 壊れた APK を公開しない (zip として読めるか)。署名の有無は runbook の 8 節で確かめる
python -c "import sys, zipfile; sys.exit(zipfile.ZipFile(sys.argv[1]).testzip() is not None)" "$APK" || { echo "APK が壊れています: $APK" >&2; exit 1; }
firebase deploy --only hosting --project project-10522535-9db8-40c0-a68
