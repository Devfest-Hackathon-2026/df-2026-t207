# WEARBY — チーム Wojak

すれ違った人の服を、話しかけずに知り、手持ちで合うかまで確かめるアプリ。

DevFest GDGoC Japan Hackathon 2026 の提出作品です。

## デプロイ URL

| 何 | URL |
|---|---|
| Web デモ (審査員向け、Firebase Hosting) | https://project-10522535-9db8-40c0-a68.web.app |
| API (`api`、Cloud Run) | https://api-591807217114.asia-northeast1.run.app |
| Android アプリ (APK) | https://github.com/Devfest-Hackathon-2026/df-2026-t207/releases/tag/v1.0 (Web デモの QR とボタンも同じ APK を指します) |

## 試し方 (Android アプリ)

APK を入れ、ログインの画面の「審査用アカウントでログイン」で入れます。アカウントとパスワードはプロダクト説明ドキュメントの 6.1 にあります。APK はデモモード (近くの人の代わりに AI 生成のデモの人物を出す) で始まるので、1 台で試せます。2 台あれば、両方の設定で「デモモード」を切ると、Bluetooth の本物のすれ違いを試せます。近くの人を見るには、先に今日のコーデを撮って公開します (お互いさま)。

## 試し方 (Web デモ)

Web デモでは、近くの人の検出 (Bluetooth) だけを模擬しています。照合と着用イメージは、毎回その場で Gemini を呼びます。

1. 上の Web デモの URL を開く。アカウントは要らず、匿名で入る (「デモを開く」が出た時は押す)
2. 画面の上に「デモモード: 近くの人は AI 生成のサンプルです」と出る。審査員は、事前に登録した見る側の架空の人物 (AI 生成) として試せる
3. 下のメニューの「探す」で、近くの人のコーデ (顔を隠し背景を消した着姿) が 1 人 1 画面で並ぶ。横にめくると次の人
4. 下にスワイプして着用アイテムを見る → 服を 1 つ選び「手持ちと照合」
5. 手持ちとの照合の結果が出る: 合う組み合わせ (最大 3 つ) と理由、足りない 1 着、似た服をもう持っているか
6. 組み合わせの「着てみる」で着用イメージが出る。その場で生成するので約 20 秒 (混んでいる時は 1 分ほど)

デモの人物 (見られる側 3 人と見る側 1 人) は、すべて AI で生成した架空の人物です。

## 何を作ったか

```
見られる側: 今日の全身写真を撮る → サーバで背景を消し顔を隠す → 服を 1 着ずつ切り抜く → 手持ちに登録される
            → 今日の公開を選ぶ → ポケットの中で匿名 ID を BLE で発信 (24 時に自動で切れる)
見る側:     アプリを開く → 直近 5 分に受け取った ID から、サーバが今日の着姿を引く
            → 気になる服を選ぶ → 手持ちと照合 → 合う組み合わせと理由 / 足りない 1 着 → 自分の着用イメージ
```

目的は、合わない服を買って着ないままにすることを減らすことです。詳しくは [docs/concept.md](docs/concept.md)。

## 構成

```
Android アプリ (Flutter + Kotlin の常駐サービスで BLE)     Web デモ (Flutter Web、Firebase Hosting)
        │ HTTPS + Firebase の ID トークン
        ▼
Cloud Run (asia-northeast1、FastAPI)
  ├ vision: 背景除去 (isnet) → 顔を隠す (YuNet) → Gemini で服の区分・重ね着・検出枠と点 → SAM 2.1 で服の領域を切り抜く
  └ api:    匿名 ID から着姿を引く処理、手持ちの登録、照合、着用イメージ、同じ服の判定、
            フレンド (実際の友人どうしの相互承認だけ。今日の公開コーデからも照合できる)、通知、ブロックと通報
        │ (vision と api の両方から)
        ├ Agent Platform: gemini-3.8-flash / gemini-nano-banana-2.1 (予備 gemini-3-pro-image) / gemini-embedding-2
        ├ Cloud Firestore
        └ Cloud Storage for Firebase (アプリからの直接の読み書きは拒否)
```

| 文書 | 中身 |
|---|---|
| [docs/concept.md](docs/concept.md) | 何を作るか、なぜ作るか |
| [docs/spec.md](docs/spec.md) | 画面と流れ |
| [docs/architecture.md](docs/architecture.md) | 構成・処理の流れ・データ・安全・費用 |
| [docs/tech-decisions.md](docs/tech-decisions.md) | 技術を選んだ理由、捨てた案、試した結果 |
| [docs/api.yaml](docs/api.yaml) | API の仕様 |
| [docs/architecture-diagram.png](docs/architecture-diagram.png) | 構成図 |

## 置き場

| ディレクトリ | 中身 |
|---|---|
| `app/` | Flutter のアプリ (Android と Web デモ)。BLE の常駐サービスは `app/android/` に Kotlin で実装 |
| `server/api/` | FastAPI の `api` (Cloud Run) |
| `server/vision/` | FastAPI の `vision` (Cloud Run。顔と背景の処理、服の切り抜き) |
| `scripts/` | Web のデプロイとデモのデータの投入 |
| `poc/ble/` | BLE の検証用アプリ (参照用) |

## 使った技術

- Google Cloud: Cloud Run、Cloud Build、Artifact Registry、Agent Platform (Gen AI SDK)
- AI モデル: `gemini-3.8-flash` (服の検出・照合・同じ服の判定 (新しく撮った服が手持ちのどれと同じ 1 着か))、`gemini-nano-banana-2.1` と予備の `gemini-3-pro-image` (着用イメージ)、`gemini-embedding-2` (同じ服の候補)
- Firebase: Authentication (Google ログイン / 審査用のメールとパスワード / Web デモは匿名)、Cloud Firestore、Cloud Storage for Firebase、Hosting、Cloud Messaging
- アプリ: Flutter 3.47.9、Dart、Kotlin (BLE の発信と受信)
- サーバ: Python 3.12、FastAPI
- 画像の処理: rembg (isnet-general-use)、OpenCV (YuNet)、SAM 2.1 tiny (Transformers)

## 安全の配慮

原則は「目で見えている以上のものは、見る側に渡さない」です。

- 見せるのは、本人が公開を選んだ今日の着姿 (顔を隠し背景を消した画像) と服の情報だけ。名前、プロフィール、過去の投稿、距離、方向は出さない
- 顔は、見つかれば顔の部分をぼかし、見つからなければ頭の部分を単色で塗りつぶす。隠した後にもう一度顔を探し、残っていれば Gemini に送らず公開もしない
- 元の全身写真はサーバのメモリの中だけで扱い、保存しない
- 公開は初期オフで、本人が手で始め、その日の 24 時に自動で切れる
- 匿名 ID は 5 分ごとに替わり、ID と本人の対応はサーバだけが持つ。見る側に渡すのは、着姿を表示するための使い捨ての ID (カード ID) だけで、30 分で切れる
- 同じ人の着姿の表示は、見る側の 1 人ごとに 1 日 1 回だけにする (目の前にいない特定の人を追い続ける使い方を防ぐ)。記録は HMAC の値だけで、誰が誰を見たかは記録から読めない (使い捨てのカードには持ち主と見た人の uid が残る。消す処理は今後)
- 見る側も、自分が今日公開している時だけ、ほかの人の着姿を見られる (お互いさま)
- ベクトル検索は本人の手持ちに絞る (服で人を探す機能にしない)。カメラで相手を照合する機能、すれ違った人への連絡やフォローは作らない
- 着用イメージは本人にだけ返し、「AI による着用イメージ」と表示する。着用イメージに使う自分の写真は、アプリのカメラで撮ったものだけを受け付ける
- 着姿の画面ではスクリーンショットを防ぐ (Android)。ブロックと通報も用意している
- ログに ID トークン・匿名 ID・素の uid を書かない

それでも、発信している人がその場にいると分かることは消せません。完全に防げるとは言わず、どう減らしたかを [docs/architecture.md](docs/architecture.md) の 5 節に書いています。

## API キーと認証について

`app/lib/firebase_options.dart` にある Firebase のクライアント用のキーは、公開が前提のキーです。呼び出し元 (Hosting のドメインと、このアプリの署名) と、Firebase の API だけに制限しています。保護は Firestore と Cloud Storage の Security Rules、および `api`・`vision` での ID トークンの検証で行っています。サーバは API キーを持たず、Cloud Run のサービスアカウントで Agent Platform を呼びます。

## チーム Wojak

| 名前 | 主な担当 |
|---|---|
| 白井 | サーバ (`api`、`vision`)、デプロイ、デモのデータ |
| 田中 | Flutter のアプリ、Android の BLE |
| 青山 | 画面のデザイン、見る側とフレンド・通知の画面の実装 |
