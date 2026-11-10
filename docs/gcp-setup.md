# Google Cloud のプロジェクトを作る手順

無料トライアル (300 ドル) を、まだ一度も使っていない Google アカウントで始める。登録は田中か青山のどちらか 1 人がやる (決め方は `docs/tech-decisions.md` の D2)。ここに書くのは登録する人の手順だけで、API の有効化など残りは白井が引き取る。

## 登録する人がやること (15 分ほど)

1. https://console.cloud.google.com/freetrial を、自分の個人の Google アカウントで開く
   - 登録の画面が出ずに「お支払い」の画面に飛ぶ時は、そのアカウントはトライアルを使ったことがある。別のアカウントにするか、白井に伝える
2. 国・利用規約に同意し、本人確認のカードを入れる
   - トライアルの間は請求されない。**「有料アカウントに切り替える」「アカウントを有効化」は押さない**。押さなければ、300 ドルを使い切るか 90 日たった時に止まるだけで、請求は来ない
3. 画面の上のプロジェクトの選択 → 「新しいプロジェクト」で作る
   - 名前: `df-hack26` (実際には登録の時に自動で作られた My First Project、ID `project-10522535-9db8-40c0-a68` を使っている)
   - 請求先: 今作ったトライアルの請求先
   - 作った後に出るプロジェクト ID を控える
4. 「IAM と管理」→「IAM」→「アクセスを許可」
   - 新しいプリンシパル: 白井の Google アカウント (アドレスは Discord で聞く)
   - ロール: 「オーナー」
5. 「お支払い」→「アカウント管理」→ 右の「権限」で、同じ白井のアカウントに「請求先アカウント管理者」を足す
   - 予算のアラートを白井が付けるため。トライアルのままなら請求は来ないので、カードに請求されることはない
6. 白井に、プロジェクト ID と、終わったことを伝える

案内の画面に出る「使ってみる」「チュートリアルを始める」などのボタンは押さない (サンプルのリソースが作られることがある)。

## 白井が引き取ること

- API の有効化: Agent Platform (Vertex AI)、Cloud Run、Firestore、Cloud Storage、Cloud Build、Artifact Registry、Firebase
- 予算のアラート (例 トライアル残りの 50% / 90%) と、Agent Platform の呼び出し回数の上限
- Firebase をこのプロジェクトに足す

## 動かす時のサービスアカウント

`api` と `vision` は専用の `df-hack26-run@project-10522535-9db8-40c0-a68.iam.gserviceaccount.com` で動かす (2026-11-08 作成)。ビルドに使う既定のアカウント (`591807217114-compute@…`) とは分ける。ビルドの中の依存のコードに利用者のデータを触らせず、動いているサービスにビルドの権限を持たせず、指定なしで作ったサービスに権限を渡さないため。

| 権限 | 範囲 | 何のため |
|---|---|---|
| `roles/datastore.user` | プロジェクト | Firestore の読み書き |
| `roles/aiplatform.user` | プロジェクト | Gemini・Embedding・画像生成の呼び出し |
| `roles/storage.objectAdmin` | バケット `project-10522535-9db8-40c0-a68.firebasestorage.app` だけ | 着姿と服の切り抜きの読み書き |

配備の時は `gcloud run deploy` に `--service-account df-hack26-run@project-10522535-9db8-40c0-a68.iam.gserviceaccount.com` を必ず付ける (付けないと既定のアカウントで動き、Firestore などを呼べない)。

- `vision` は誰でも呼べる設定 (`allUsers` に `run.invoker`、2026-11-08 白井さん)。アプリが持てるのは Firebase のログインだけなので。守りは中のログインの確認・1 人 1 日 20 回・最大 3 台
- `api` の本物は、普段の通信を流さない版 `https://real---api-r3ctigwgiq-an.a.run.app` (tag `real`)。アプリのログインがつながったら普段の URL に切り替える。配備し直す時は `--no-traffic --tag real`
- `api` の `VIEWLOG_SECRET` (1 日 1 回の記録の HMAC の鍵) は Cloud Run の環境変数にだけ置く。配備し直す時は `--update-env-vars` で他の値を足し、`--set-env-vars` で消さない (変わると、その日の 1 日 1 回の記録が外れる)

## 確かめたこと

- 2026-11-08: `gemini-3.8-flash`・`gemini-nano-banana-2.1`・`gemini-3-pro-image`・`virtual-try-on-001` (東京) はこのプロジェクトから呼べた。`gemini-2.5-flash` と Robotics-ER 1.6 は 404
- 白井のアカウントからは、まだ請求先が見えない (5 の権限を足してもらう)
