# app

Flutter のアプリ (Android と Web デモ)。Flutter 3.47.9。

- applicationId / パッケージ: `jp.dfhack26.app` (Firebase にアプリを登録する時に使う)
- Android の minSdk: 31 (BLE の常駐の権限が Android 12 から)
- 常駐の BLE は `android/` に Kotlin で書く (`poc/ble/` から移す、tasks の A3)
- 見る側の画面は `lib/viewer/` に置き、Android と Web で同じコードを使う

## 動かす

```sh
cd app
flutter pub get
flutter test
flutter run -d chrome --web-port 8080     # Web デモ (匿名で本体に入り、「模擬」の帯が出る)
flutter run                               # Android の実機
```

- 既定は配備済みの本番 API と画像処理サービス。接続先は `--dart-define=API_BASE_URL=...` と `--dart-define=VISION_BASE_URL=...` で切り替えられる
- Web は Firebase Hosting または `localhost` から API に接続する。手元で確認する時は `127.0.0.1` ではなく `localhost` を使う
- ログインは Firebase Auth (`lib/services/firebase_auth_service.dart`)。Android は Google、Web は匿名
- Android の Google ログインには、各自の PC の debug の SHA-1 を Firebase に登録する (`cd android && ./gradlew signingReport` の `Variant: debug` の SHA1 を白井に送る)
- 既定の接続先は普段の api の URL (`https://api-591807217114.asia-northeast1.run.app`、2026-11-09 から本物)。仮の api に戻す時は白井が流れ先を替える
- Android の近くのコーデは、設定の「デモモード」で AI 生成のデモの人物 (`POST /v1/demo/nearby`) と本物の BLE を切り替える。`--dart-define=MOCK_NEARBY=true` で作るとデモモードで始まる (切り替えは端末に残る)。デモの人物を見るにも、今日のコーデを登録して公開しておく
- Android のデバッグビルドで撮影写真を差し替える場合は、端末のアプリ内領域にテスト画像を置き、`--dart-define=OUTFIT_TEST_PHOTO_PATH=/data/user/0/jp.dfhack26.app/files/outfit-test.png` を指定する。通常のコーデ投稿の写真確認と送信に使う

## リリースビルド

次のコマンドは `app/` で実行する。既定の接続先は本番 API。

```sh
flutter build appbundle --release
flutter build web --release
```

Android の配布用ビルドは、ローカルの `android/key.properties` に `storeFile`、`storePassword`、`keyAlias`、`keyPassword` を設定すると署名される。相対パスの `storeFile` は `android/` から解決する。このファイルが無い場合は未署名の成果物ができる。Google ログイン用に、配布するアプリの署名証明書の SHA-1 を Firebase に登録する。

配布鍵がない環境でエミュレーターを確認する場合は、`flutter build apk --release` で作った未署名 APK のコピーを Android SDK の `apksigner` でデバッグ鍵を使って署名する。既存のデバッグ版と同じ鍵なら上書きできる。

## 置き場

| 場所 | 中身 |
|---|---|
| `lib/main.dart` | 入口。認証と api の部品を作って渡す |
| `lib/app/` | 画面のつなぎ。初回 (ログイン → 名前 → 最初のコーデの案内) と、本体 (ホーム・マイページに api のデータを渡す) |
| `lib/api/` | api を呼ぶ部品と、`docs/api.yaml` の形のデータ。画像の口は `ApiClient.image()` で同じ認証で読む (Web でも動く) |
| `lib/services/` | 認証の窓口 (`AuthService`) |
| `lib/ble/` | すれ違いの検出の窓口 (`BleController`)。Android は下の常駐につなぎ、Web は何もしない |
| `android/.../ble/` | BLE の常駐 (Kotlin、`poc/ble/` から移した)。公開中だけ発信と受信を続け、受け取った ID は直近 5 分だけメモリに持つ |
| `lib/shell/` | 下のメニューと、タブの切り替え (`AppShell`) |
| `lib/auth/`、`lib/capture/` | ログイン・名前・初回の案内、カメラと撮影後の確認の画面 |
| `lib/home/`、`lib/mypage/`、`lib/common/` | ホーム、マイページ、共通の部品 |

## まだのこと

- **A4**: 写真確認で「投稿」すると、Firestore で処理状況の購読を始めてから `vision` に送る。処理中も他の画面を使える。完了後は通知から服を確認し、今日のコーデと手持ちに登録する。投稿には Google ログインが必要
- **投稿の通知**: Android はアプリが処理完了を受け取った時に端末へ通知する。未登録の結果は次の起動時にも確認できる。プロセスが終了している間の配信には、サーバからのプッシュ通知が必要
- **A5 (済、実機は未確認)**: 公開のスイッチで `PublishingController` が `PUT /v1/publish` → 常駐の開始、非公開で常駐の停止 → `PUT /v1/publish`。許可は後で設定画面につなぐ (現時点では未接続)。サーバが公開中で常駐が止まっていれば起動時に始め直す
- **A3 の実機の確認**: BLE はエミュレータで確かめられない。実機 2 台で、発信と受信、画面オフでの継続、24 時の停止を見る (Kotlin の中身の決まりは `cd android && gradlew :app:testDebugUnitTest` で確かめられる)

## BLE の常駐 (A3)

- 発信: 接続しない広告。UUID `6a3f9c21-…` (poc と同じ) の ServiceData に「匿名 ID 11 バイト + 送信の強さ 1 バイト」
- ID は `PUT /v1/publish` で受け取った並びから「今の時刻の枠の物」を選ぶ (画面オフでタイマーが遅れても枠と ID がずれない)。その日の 24 時に自分で止まる
- 受信: 画面が前にある間は速いスキャン、裏では普通のスキャン。9.5 分ごとに張り直す (poc の実測どおり)
- OS に止められても戻れるよう、設定は端末の中に置き `START_STICKY`。ログに匿名 ID を書かない
- Flutter とは `MethodChannel jp.dfhack26.app/ble` (capabilities・permissions・requestPermissions・start・stop・status・sightings) と `EventChannel jp.dfhack26.app/ble/status`
- 探す (近くのコーデ、A2) とコミュニティはまだ「準備中」の画面
