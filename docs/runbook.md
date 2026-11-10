# 配備と当日の手順 (11/10 の締めから決勝まで)

本物の配備は白井 (の Claude) が行い、毎回チームの了承を取る。命令は PowerShell で流す前提 (Bash から `gcloud.cmd` を呼ぶと、`^;^` などの引数が cmd で不正になる)。

```powershell
$G = "$env:LOCALAPPDATA\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd"
$P = 'project-10522535-9db8-40c0-a68'
$SA = "df-hack26-run@$P.iam.gserviceaccount.com"
$IMG = "asia-northeast1-docker.pkg.dev/$P/cloud-run-source-deploy"
```

## 今の形 (2026-11-09 未明)

| サービス | URL | 中身 |
|---|---|---|
| `api` | `https://api-591807217114.asia-northeast1.run.app` (tag `real` の `https://real---api-r3ctigwgiq-an.a.run.app` も同じ版) | 本物に 100%。フレンド・通知・いいね・保存まで全部の口。デモの人物は demo-haru・demo-ken・demo-mio、見る人は demo-viewer |
| `vision` | `https://vision-591807217114.asia-northeast1.run.app` | 本物。誰でも呼べる (中でログインと回数を確かめる)。顔は目から顎までをぼかし、処理が終わったら通知する |

仮の api (見本を返す) の版 `api-00003-7m8` は残っている。戻す時は 3 の「戻す時」。

どちらも専用のサービスアカウント `df-hack26-run@` で動く (`docs/gcp-setup.md`)。

11/10 の締めの前の最後の配備 (この版で 11/14 の終わりまで凍結): `api-00025-ps7` (フレンドの服からの照合・通知の題 WEARBY・回数の上限を広げた設定)、`vision-00016-6p6`、Web と APK は main の `9f4c26e` 以降。おかしい時に戻す先の 1 つ前は `api-00024-qqh` と `vision-00015-j7q`

## 1. 組み立てと配備

```powershell
# リポジトリの一番上で
& $G builds submit --project=$P --region=asia-northeast1 --config server/api/cloudbuild.yaml .
# server/vision で (5 分ほど)
& $G builds submit --project=$P --region=asia-northeast1 --config cloudbuild.yaml .

# api を配備する。普段の URL にそのまま出す (11/9 夜に通信を「常に最新の版へ」に戻した)。
# :latest の文字列は前と同じなので、digest を指定する (同じ文字列だと新しい版にならないことがある)
$D = & $G artifacts docker images describe "$IMG/api:latest" --format='value(image_summary.digest)'
& $G run deploy api --project=$P --region=asia-northeast1 --image="$IMG/api@$D" --service-account=$SA --quiet
# 通信が最新の版に 100% 流れているかを必ず確かめる (latestRevision: True)
& $G run services describe api --project=$P --region=asia-northeast1 --format='value(status.traffic)'
& $G run deploy vision --project=$P --region=asia-northeast1 --image="$IMG/vision:latest" --service-account=$SA --quiet
# vision の通信が前の版に固定されている時 (--no-traffic で配備した後など) は、最新の版に切り替える
& $G run services update-traffic vision --project=$P --region=asia-northeast1 --to-latest
```

- 環境変数は配備し直しても残る。足す時は `--update-env-vars`、消す時は `--remove-env-vars`。`--set-env-vars` と `--env-vars-file` は全部を置き換えるので、`VIEWLOG_SECRET` (1 日 1 回の記録の鍵) と `ADMIN_TOKEN` を消さないように注意する
- 値に「,」が入る環境変数 (`DEMO_UIDS` など) は、PowerShell からは `--update-env-vars` で渡せない。今の値を読んで YAML に書き、`--env-vars-file` で丸ごと入れる (下の 4)

## 2. 確かめる

```powershell
python scripts/smoke_api.py            # 普段の URL (審査員が使う物)
```

匿名の審査員と同じ流れ (自分と今日のコーデ → 模擬の検出 → カードの画像 → 照合 → 着用イメージ → 手持ち) を流し、全部 `OK` なら良い。照合と着用イメージは本物の生成を呼び、匿名の 1 日の上限を 1 回ずつ使う。tag `real` は 11/9 夜の古い版を指しているので、確かめには使わない

## 3. 普段の URL を本物に切り替える (アプリのログインがつながった後)

```powershell
& $G run services update-traffic api --project=$P --region=asia-northeast1 --to-tags=real=100
```

(2026-11-09 未明に切り替え済み。ただしこの切り替えは通信を版 api-00013-xog に固定したので、11/9 夜の配備が出なかった。
11/9 21:31 に `update-traffic api --to-latest --update-tags=real=api-00015-2l6` で最新の版に流すよう戻した。以後は `--no-traffic` を付けずに配備すれば、そのまま普段の URL に出る。
配備した後は `run services describe api --format='value(status.traffic)'` で `latestRevision: True` を確かめる。
`--image=…/api:latest` は前と同じ文字列なので、版が作られても通信が動いたか分かりにくい)

- 戻す時: `--to-revisions=api-00003-7m8=100` (仮の api の版)
- 切り替えた後は、アプリの `--dart-define=API_BASE_URL` なしで本物につながる

## 4. デモの人物を入れる・入れ替える

1. `python scripts/seed_demo.py <素材のフォルダ> --prefix demo` (最後に環境変数が出る)
2. `python scripts/precompute_demo.py --viewer demo-viewer --owners <見られる側の uid,...>` (画像の生成は 1 分 4 回までなので、20 枚で 10 分ほど)
3. api の環境変数を入れ直す。`DEMO_UIDS` (判定から外す見られる側。カードに「AI 生成」の印が付くので、壇上の A は入れず `ONCE_A_DAY_EXEMPT_UIDS` に入れる)、`WEB_DEMO_UIDS` (Web の模擬の検出に出す人。壇上の A は入れない)、`DEMO_VIEWER_UID` (Web の審査員が成り代わる見る人)

```powershell
$env_ = (& $G run services describe api --project=$P --region=asia-northeast1 --format=json | ConvertFrom-Json).spec.template.spec.containers[0].env
$keep = @{}; foreach ($e in $env_) { $keep[$e.name] = $e.value }
$keep['DEMO_UIDS'] = '<...>'; $keep['WEB_DEMO_UIDS'] = '<...>'; $keep['DEMO_VIEWER_UID'] = '<...>'
$f = "$env:TEMP\api-env.yaml"
($keep.GetEnumerator() | ForEach-Object { "$($_.Key): '$($_.Value)'" }) -join "`n" | Set-Content -Path $f -Encoding utf8NoBOM
try { & $G run deploy api --project=$P --region=asia-northeast1 --image="$IMG/api:latest" --service-account=$SA --env-vars-file=$f --quiet } finally { Remove-Item $f -Force }
```

(切り替えの前は `--no-traffic --tag=real` を足す)

4. 試験の人物 (`trial-…`、Commons の写真) を消す: Firestore の `users/trial-*` と `precomputed/*_trial-*`、Storage の `users/trial-*/` と `precomputed/trial-*`

## 5. 台数

提出の 19:00 から 11/14 の終わりまでは実行環境を凍結する決まり (運営の「提出物・提出ルール」の 4 節。再配備・設定の変更・手での再起動は不可) なので、台数は 19:00 より前に入れて、そのままにする。凍結の前に長く起動したままでも崩れないかを見るため、前倒しで入れた。台数の設定は配備し直しても引き継がれる。

| いつ | api | vision |
|---|---|---|
| 2026-11-09 22 時から 11/14 の終わりまで (入れ済み、版 api-00016-9rc と vision-00012-rcv) | 最小 1 台 | 最小 1 台 (つけっぱなし、白井さんが決定。費用は約 6,000 円の見込み) |
| 決勝 (11/27) に進んだ場合 | 運営の案内を見て決める | 同左 |

```powershell
& $G run services update api --project=$P --region=asia-northeast1 --min-instances=1
& $G run services update vision --project=$P --region=asia-northeast1 --min-instances=1
```

## 6. 締めの前の片付け (11/10 15:00 の最後の配備まで)

- (済、11/9 夜) vision の計測用の口 `/bench` を消し、`BENCH_TOKEN` を外した (版 vision-00014-gg4)
- 試験の匿名ユーザーの処理の結果 (Storage の `users/<匿名の uid>/jobs/smoke_*`) を消す

## vision のビルドの注意

- 重み (isnet・SAM 2.1・YuNet、約 650MB) は Storage の `gs://project-10522535-9db8-40c0-a68.firebasestorage.app/build-models/models/` に置き、`server/vision/cloudbuild.yaml` の最初の段で落とす (Cloud Build から GitHub の isnet の配布が 504 になり、ビルドが続けて落ちたため)。**この置き場を消さない**。消えても `fetch_models.py` が元の配布から取り直すが、その日に 504 なら落ちる。アプリからは Security Rules で読めない
- 0 台からの起動は 26〜35 秒 (2026-11-08、前は 101 秒。ファイルの読み込みの待ちで回ごとに揺れる)。効いたのは `NUMBA_CPU_NAME=generic` (起動のたびの numba の翻訳 約 40 秒を止める) と、transformers の使わないモデルのソースを消したこと。起動の時の先読みは逆に 10 秒遅くなったので入れていない

## 7. 困った時

| 起きたこと | 手当て |
|---|---|
| 着用イメージが 502 (混んでいる) | 画像の生成はモデルごとに 1 分 2 回 (申請で増やせない)。api は予備のモデルに回し、待ってやり直している。続くなら画面で「混んでいます」と出すだけ |
| AI の費用が心配・AI が落ちている | `& $G run services update api ... --update-env-vars=AI_DISABLED=1`。照合と着用イメージは事前の結果だけを返し、無ければ 503 |
| 本物の api がおかしい | 3 の「戻す時」で仮の api の版に戻す。Cloud Run の版は `& $G run revisions list --service=api ...` |
| 壇上の練習で「1 日 1 回」に当たった | 壇上の A が `ONCE_A_DAY_EXEMPT_UIDS` に入っているか確かめる (入っていれば 1 日 1 回は効かない) |

## 8. Web デモの外枠・審査員向けの APK・キーの制限 (2026-11-09 夜)

- PC の広い画面 (幅 1000 以上) では、アプリをスマホの枠に入れ、左に説明と APK の QR、中央に「すれ違った人 A の画面」を並べる (`app/lib/app/web_stage.dart`)。A の画面は、B が「探す」で今見ているカードの着姿を出し、B のいいねを通知で受ける (同じアプリの中で描くので 2 つ目のログインは要らない)。狭い画面は全画面のままで、デモの帯に「Android アプリ」の link を置く
- APK は Hosting の `/wear-by.apk` に置いた (模擬の検出入り、この PC の debug 鍵で署名、Google ログイン)。作り直す時:

```sh
cd app && flutter build apk --release --dart-define=MOCK_NEARBY=true
cp build/app/outputs/flutter-apk/app-release.apk build/web/wear-by.apk   # flutter build web の後に。deploy_web.sh は無ければ公開中の物を取ってくる
```

- `MOCK_NEARBY=true` はデモモード (近くの人の代わりに AI 生成のデモの人物を出す) の初めの値。配る APK はデモモードで始まり、アプリの設定の「デモモード」で切ると本物の BLE になる (切り替えは端末に残る。11/10 から)。撮影と壇上の 2 台は、設定でデモモードを切る
- 署名の鍵は、Firebase に SHA-1 を登録した 3 つのどれかでないと Google ログインが通らない (この PC の debug 鍵 `89A0…7E3B` は登録済み)。Android 用の Firebase のキーも、同じ 3 つの SHA-1 からの呼び出しだけを通す
- 11/9 23 時の青山さんの変更 (966102a) で、release の build は `android/key.properties` の鍵で署名する形になった。key.properties の無い PC で release を作ると署名の無い APK ができ、入らない。新しい鍵で作るなら、その SHA-1 を Firebase と Android 用のキーの両方に足してから出す。今公開中の APK は、この PC の debug 鍵で署名した 11/9 22 時の物
- APK を差し替える時は `APK_FILE=<作った APK> ./scripts/deploy_web.sh`。出した後に `/wear-by.apk` を落として 1 台に入れ、Google ログインまで確かめる
- Firebase のクライアント用のキー (2 つ) は、使える API を Firebase の物だけに絞ってあり (自動で作られた時から)、11/9 夜に呼び出し元も絞った: ブラウザ用は `https://project-10522535-9db8-40c0-a68.web.app/*` と `.firebaseapp.com/*`、Android 用は `jp.dfhack26.app` + 登録済みの SHA-1 3 つ。手元の `flutter run -d chrome` からは匿名ログインが通らない (api の CORS もそもそも手元を通さない)
- 戻す時 (ログインが止まった時): `& $G services api-keys update <uid> --project=$P --clear-restrictions` は API の制限まで消すので使わない。`--allowed-referrers` / `--allowed-application` を付け直すか、コンソールの「API とサービス → 認証情報」でアプリケーションの制限だけを「なし」に戻す

## 9. Web デモの審査員 (匿名) とデモの見る人 (2026-11-10 未明)

- 匿名の審査員は demo-viewer (名前 Demo) として動き、自分の情報と今日のコーデには、demo-viewer の一番新しい画像付きの記録を「公開中 (今日の 24 時まで)」で返す (日付に依らないので、凍結の後もデータを足さずに出る)。今は 11/10 の記録 (パーカー・デニム・スニーカー) を手で足してある
- `scripts/seed_demo.py` を流し直すと demo-viewer の記録が消え、名前も「デモの見る人」に戻る。流し直した時は、11/10 の記録と名前 (Demo) を足し直す
- 照合と着用イメージは、デモの人物でも毎回その場で作る。事前の結果は `AI_DISABLED=1` の時だけ、画面に「事前に作った」と出して返す
- 匿名の審査員の 1 日の上限は全員で共有する。11/10 に `QUOTA_ANON_TRYON=500`、`QUOTA_ANON_MATCH=1000` に広げた (既定は 30 と 100)。ログインした人 1 人の上限も `QUOTA_TRYON=30`・`QUOTA_MATCH=60` (api)、`QUOTA_VISION=40` (vision) に広げた (当日の練習で尽きないように)。一番多く使われても 11/14 までで約 $240 の見込み。凍結の後は変えられない
