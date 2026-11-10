# AGENTS.md

このリポジトリで作業する AI (Claude Code、Codex、Gemini CLI など) と人が守る決まり。3 人がそれぞれの AI で同時に書くので、置き場と正本を揃えるのが目的。

## 最初に読む物

| 何 | どこ |
|---|---|
| 何を作るか | `docs/concept.md` |
| 画面と流れ (仕様書) | `docs/spec.md` |
| 構成と処理の流れ・データ・安全 | `docs/architecture.md` |
| 決めた理由・捨てた案・試した結果 | `docs/tech-decisions.md` |
| 作業の順番と依存、主な担当の目安 | `docs/tasks.md` |
| API の仕様 (正本) | `docs/api.yaml` (tasks の F2 で作る) |

食い違ったら、`docs/api.yaml` > `docs/architecture.md` > `docs/spec.md` の順で正しい。直す時は食い違った両方を直す。

## 置き場

| ディレクトリ | 中身 | 主に触る人 |
|---|---|---|
| `app/` | Flutter のアプリ (Android と Web デモ)。常駐の BLE は `app/android/` に Kotlin | 田中 |
| `app/lib/viewer/` | 見る側の画面 (Android と Web で共通) | 青山 |
| `server/api/` | FastAPI の `api` (Cloud Run、軽い方) | 白井 |
| `server/vision/` | FastAPI の `vision` (Cloud Run、重い方。頭・背景・Gemini・SAM) | 白井 |
| `scripts/` | Web の配備 (`deploy_web.sh`)、煙試験、デモのデータの投入 | 白井 |
| `docs/` | 設計の文書。`docs/mockups/` は青山さんの画面のイメージ | 全員 |
| `poc/ble/` | BLE の検証用アプリ (参照用。製品のコードは `app/` に書く) | — |

担当は目安。別の人の置き場を変える時は、その変更だけの小さな commit にし、メッセージに理由を書く。

## 書き方

- 版: Flutter 3.47.9、Python 3.12、Kotlin は Flutter の既定に合わせる
- 改行は LF (`.gitattributes` で固定)。文字コードは UTF-8
- API の形を変える時は、先に `docs/api.yaml` を直して push し、それから実装する
- 画面の文言は日本語。説明の文を足すより、見出しとラベルで分かるようにする
- 使うモデルの名前は `docs/architecture.md` のとおり (`gemini-3.8-flash`、`gemini-nano-banana-2.1` と予備の `gemini-3-pro-image`、`gemini-embedding-2`)。勝手に替えない

## 安全の決まり (コードで破らない)

- 他人に見せる着姿は、顔を隠し (ぼかすか、顔が見つからない時は頭を塗る) 背景を消した物だけ。Gemini に送るのも同じ画像だけ (例外は、着用イメージに使う本人の写真)
- フレンドは実際の友人どうしの相互承認だけ。すれ違いのカードから追加できる道を作らない。フレンドに見せるのはその日の公開コーデだけ
- 元の全身写真はサーバのメモリの中だけで扱い、保存しない
- 見る側に渡すのは使い捨てのカード ID だけ。手持ちの服の id・uid・匿名 ID を見る側に返さない
- ベクトルの検索は必ず本人の手持ちに絞る
- 同じ人の着姿は見る人ごとに 1 日 1 回 (`DEMO_UIDS` の例外あり)。お互いさま
- ログに ID トークン・匿名 ID・素の uid を書かない
- 詳しくは `docs/architecture.md` の 5 節

## 鍵と公開

- API キー・サービスアカウントの鍵・`.env` は commit しない。値は `.env` に置き、名前だけを `.env.example` に書く
- 例外: Firebase のクライアント用の設定 (`app/lib/firebase_options.dart`) は公開が前提なので commit する。守りは Security Rules と、api・vision の ID トークンの検証 (`docs/tech-decisions.md` の 8 節)。`google-services.json` は commit しない
- サーバは鍵を持たず、Cloud Run のサービスアカウントで Agent Platform を呼ぶ
- 顔の写る実在の人の写真と、`docs/mockups/` 以外の写真を入れない。デモの人物は AI で作った架空の人物 (「AI 生成」と明示)
- このリポジトリは private。提出用の public のリポジトリへは、提出の時に `README.md` の手順で必要な物だけを持って行く

## git

- PR は使わず `main` に直接 push する。push の前に `git pull --rebase`
- commit は小さく、1 つの変更に 1 つ。メッセージは日本語で、何をなぜ
- 作業を始める時は `docs/tasks.md` の「取った人」に名前を書いて push する
- 締め: 11/9 18:00 に機能の追加を止める。11/10 15:00 が最後の配備
