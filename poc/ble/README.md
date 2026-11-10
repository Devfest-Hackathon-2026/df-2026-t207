# すれ違い検証 (BLE / Nearby) の測り方

検証用の Android アプリ `jp.wojak.blepoc` (表示名「すれ違い検証」) で、2 台の実機を使って次の 3 つを測る: 検出の速さ、画面オフでの発信の継続、電池。調べた結果と実装上の注意は `research/tech-stack/detection.md` (末尾の「反証役の訂正」を含む) にある。

- ここに置いたのはソースの写し。ビルドは Google Drive の外の `%LOCALAPPDATA%\df-hack26\ble-poc` で行う (Drive の中でビルドすると同期が壊れる)
- ビルド: `cd %LOCALAPPDATA%\df-hack26\ble-poc` → `gradlew.bat assembleDebug` (JDK 17 以上。手元は Temurin 21)。`local.properties` に `sdk.dir=...` を書く (写しには入れていない)
- APK: `%LOCALAPPDATA%\df-hack26\ble-poc\app\build\outputs\apk\debug\app-debug.apk`
- 構成: AGP 9.4.1 / Gradle 9.6.0 / Kotlin 2.4.21 / Compose。compileSdk 37、targetSdk 34 (Android 15 以降の挙動の変更を検証の変数に入れないため)、minSdk 31。依存は Compose と `play-services-nearby` 19.5.1 だけ

## アプリの中身

| 部分 | 何をするか |
|---|---|
| 常駐 | foreground service (`connectedDevice` 型、通知あり) の中で発信と受信をする。始めるのは画面の「適用」だけ (Android 12 以降は裏から FGS を始められない)。OS に殺されても自分で戻らない (`START_NOT_STICKY`)。戻すと「止まったか」の試験が見えなくなるため |
| BLE の発信 | 接続しない広告 (`setConnectable(false)`、端末名と送信電力を載せない)。128 ビットの独自 UUID `6a3f9c21-7d4b-4e58-9b1a-2c8e5f0d7a44` の ServiceData に 12 バイトの ID (合計 30 バイト)。「載せ方」で manufacturer data (会社 ID 0xFFFF、先頭 2 バイトの印 `57 4A` + ID) に切り替えられる |
| BLE の受信 | フィルタ付きのスキャン。ServiceData のフィルタは空の配列 (`ByteArray(0)`、null だと照合で落ちる)。受信側は 2 つの載せ方のどちらでも当たるフィルタを両方張る (送り手の設定に合わせなくてよい)。`CALLBACK_TYPE_ALL_MATCHES` |
| スキャンの回数の制限 | 30 秒に 5 回まで (AOSP の既定)。アプリは直近 30 秒に 4 回張っていたら後にずらし、`rx_deferred` を書く。10 分でフィルタ付きでも LOW_POWER に落とされるので、9.5 分ごとに張り直す |
| 画面を開いた時 | 画面が前面に来たら、スキャンを「画面を開いている時」のモードで張り直す (本番の「開いてからスキャン」と同じ測り方)。裏に回ったら「常駐中」のモードに戻す (同じモードなら張り直さない)。Nearby は開いた時に探索を始め直す |
| ID の切り替え | 端末で作る 12 バイトの乱数。間隔 (既定 5 分) ごとに広告を止めて新しい ID で始め直す (MAC も変わるかを見るため)。「適用」を押した時も新しい ID にする。タイマーは普通の Handler なので、Doze では遅れる。遅れは `id_rotate` の `late_ms` に出る (それ自体が測る値) |
| Nearby | `play-services-nearby` の Connections。P2P_CLUSTER で advertise と discovery。endpointInfo に 12 バイトの ID。`requestConnection` は呼ばない。相手から接続を求められたら断る。RSSI は取れない |
| 画面 | 方式・発信/受信の ON/OFF・受信のモード (常駐中 / 画面を開いている時)・広告のモード・送信の強さ・載せ方・ID の間隔・端末の名前、端末の対応の値、許可の状態、直近 3 分の受信の一覧 (ID の先頭 4 バイト・RSSI・何秒前)、画面を開いてから最初の受信までの秒数 |

設定を変えたら「適用」を押す (押すまで効かない。画面に「まだ適用していない変更がある」と出る)。

### adb から条件を切り替える (画面に触らずに済む)

アプリを開く intent に extra を付けると、その設定を保存して「適用」と同じことをする。電池の試験の条件の切り替えに使う。

```
adb -s <serial> shell am start -n jp.wojak.blepoc/.MainActivity --es label note10 --es method BLE --ez tx true --ez rx false --es advMode BALANCED --es txPower MEDIUM --ei rotateMin 5
adb -s <serial> shell am start -n jp.wojak.blepoc/.MainActivity --ez tx false --ez rx false   # 全部止める
```

付けられる extra: `method` (BLE / NEARBY)、`tx` `rx` (true / false)、`bgScan` `fgScan` (LOW_POWER / BALANCED / LOW_LATENCY)、`advMode` (同じ 3 つ)、`txPower` (ULTRA_LOW / LOW / MEDIUM / HIGH)、`payload` (SERVICE_DATA / MANUFACTURER)、`rotateMin` (分、`--ei`)、`label`。付けなかった項目は前の設定のまま。アプリが前面に来るので、その後に画面を消す。

### ログ (CSV)

場所: `/sdcard/Android/data/jp.wojak.blepoc/files/logs/blepoc_YYYYMMDD.csv` (1 日 1 ファイル、追記)。行ごとに flush するので、プロセスが殺されても直前まで残る。

| 列 | 中身 |
|---|---|
| time_ms, iso | 端末の時計 (ms、ISO) |
| event | 下の表 |
| method | ble / nearby |
| rx_id | 受け取った ID (12 バイトの hex、24 文字) |
| rssi | dBm (Nearby は空) |
| label | 端末の名前 |
| screen_on | 1 = 画面 on |
| app_fg | 1 = アプリの画面が前面 |
| rx_mode | その時の受信のモード (LOW_POWER / BALANCED / LOW_LATENCY / nearby) |
| tx_id | その時に自分が出している ID |
| addr | BLE は相手の MAC (ID の切り替えで変わるかを見る)、Nearby は endpointId |
| detail | 失敗の理由、設定、秒数など |

| event | いつ |
|---|---|
| rx | 受け取るたび (BLE は広告 1 回ごと、Nearby は onEndpointFound) |
| first_rx | 画面を開いた後の最初の受信 (detail に秒数) |
| rx_start / rx_stop / rx_fail / rx_deferred | スキャン (探索) の開始・停止・失敗・回数の制限による後回し |
| rx_lost | Nearby の onEndpointLost |
| tx_start / tx_stop / tx_fail | 発信の開始・停止・失敗 (`DATA_TOO_LARGE` などの名前で書く) |
| id_rotate | ID を替えた (tx_id が新しい ID) |
| ui_open / ui_close | 画面が前面に来た / 裏に回った |
| screen_on / screen_off | 画面の点灯・消灯 |
| hb | 常駐の生存の印 (60 秒ごと。CPU が眠っている間は間が開く) |
| apply, svc_create, svc_destroy, task_removed, caps, perm_result | 設定の適用、サービスの始まりと終わり、最近の一覧から消された、端末の対応の値、許可の結果 |

## 準備 (毎回)

以下、`adb` は `%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe`。**必ず `-s <serial>` を付ける** (`emulator-5554` が残っている)。Note10+ は `RF8MB0KRY3Y`、S25 Ultra は下の 5 節で出る serial。

1. 両方に入れる: `adb -s RF8MB0KRY3Y install -r app-debug.apk`
2. 許可: 画面の「足りない許可を求める」で付ける。adb で付けるなら
   ```
   adb -s <serial> shell pm grant jp.wojak.blepoc android.permission.BLUETOOTH_SCAN
   adb -s <serial> shell pm grant jp.wojak.blepoc android.permission.BLUETOOTH_ADVERTISE
   adb -s <serial> shell pm grant jp.wojak.blepoc android.permission.BLUETOOTH_CONNECT
   # Android 12 (Note10+) だけ: Nearby に要る位置
   adb -s <serial> shell pm grant jp.wojak.blepoc android.permission.ACCESS_FINE_LOCATION
   adb -s <serial> shell pm grant jp.wojak.blepoc android.permission.ACCESS_COARSE_LOCATION
   # Android 13 以上 (S25 Ultra) だけ: 通知と Nearby の Wi-Fi
   adb -s <serial> shell pm grant jp.wojak.blepoc android.permission.POST_NOTIFICATIONS
   adb -s <serial> shell pm grant jp.wojak.blepoc android.permission.NEARBY_WIFI_DEVICES
   ```
3. 端末の名前を付ける (例 `note10` と `s25u`)。ログはこの名前で区別する
4. Nearby を試す時、Note10+ (Android 12) は位置情報のスイッチが ON でないと動かない (画面の「許可」の欄に ON/OFF が出る)
5. 時計のずれ (発信側から受信側までの秒数を出す時だけ要る): 2 台を同じ PC につないで、続けて打つ
   ```
   adb -s <受信側> shell date +%s%3N; adb -s <発信側> shell date +%s%3N
   ```
   (PowerShell でも cmd でも 1 行で打てる。cmd では `;` を `&` にする) 2 つの数の差 (受信側 - 発信側) を `--offset-ms` に渡す。続けて打つ間の数十 ms は誤差に入る。2 台とも自動の時刻合わせなら、ずれは数十〜数百 ms のことが多い。秒の 1 桁目より細かい差は信用しない

## 1. 検出の速さ

### 1-a. 画面を開いた時 (見る側が開いてから最初の ID が出るまで)

- 発信側: 方式 BLE、発信 ON、受信 OFF、広告 BALANCED、送信 MEDIUM → 適用。画面を消してポケット (か机の上) に置く
- 受信側: 方式 BLE、受信 ON、発信 OFF、「画面を開いている時」LOW_LATENCY → 適用
- 距離 1 m / 5 m / 10 m のそれぞれで 20 回: 受信側でホームに戻る → アプリを開く → 「画面を開いてから最初の受信」の秒数が出るのを待つ → ホームに戻る。**1 回ごとに 15 秒以上空ける** (開く時と閉じる時にスキャンを 1 回ずつ張り直し、アプリは 30 秒に 4 回までに抑えるので、続けられるのは 30 秒に 2 回)。速く回したい時は「常駐中」も LOW_LATENCY にする (閉じる時に張り直さなくなり、8 秒おきで足りる)。制限に当たると `rx_deferred` が出て、張り直しが後回しになる。その間は前のスキャンが続くので、その回の秒数は「開いてからスキャンを始めた」値にならない。`analyze.py open` はその回を数えずに、回数だけ出す
- Nearby も同じ (両方の方式を Nearby にして適用)
- 距離ごとにラベルを変えるか、メモに時刻を残す (CSV は時刻で分けられる)
- 出し方: `python analyze.py open logs/s25u/blepoc_YYYYMMDD.csv`

### 1-b. 常駐の時 (見る側がポケットの中で、新しい ID が出てから受け取るまで)

- 発信側: ID の間隔を **1 分** にして適用 (1 分ごとに新しい ID が出る。新しい ID を最初に受け取るまでの時間が、常駐での検出の時間になる)
- 受信側: 受信 ON、「常駐中」を LOW_POWER / BALANCED / LOW_LATENCY のどれかにして適用 → 画面を消してポケットに入れる
- 1 つのモードで 20 分 (20 回)。距離は 1 m と 5 m
- 出し方: `python analyze.py latency logs/note10/blepoc_YYYYMMDD.csv logs/s25u/blepoc_YYYYMMDD.csv --offset-ms <ずれ>`。受信側の画面 on/off・前面/裏・モードごとにまとめて出る
- Nearby も同じ (Nearby は Doze で遅くなるという報告があるので、画面オフで 10 分以上置いた後の値を見る)

## 2. 画面オフでの発信の継続 (10 分と 60 分)

- 電池の最適化は既定のまま (「制限なし」にしない)
- 発信側: 発信 ON (BLE、BALANCED、MEDIUM、ID の間隔 5 分) → 適用 → 画面を消してポケットか机に置く。触らない
- 受信側: 受信 ON (常駐中 BALANCED) → 適用。画面は消えてよい (フィルタ付きのスキャンは画面オフでも続く)。受信側も止まると区別できないので、受信側は USB で PC につないで充電しながらがよい
- 10 分と 60 分の後に、両方のログを取り出して
  ```
  python analyze.py gaps logs/s25u/blepoc_YYYYMMDD.csv --sender logs/note10/blepoc_YYYYMMDD.csv --gap 30
  ```
  30 秒を超える途切れと、最後に受け取った時刻が出る。発信側のログの `hb` が途中で止まって `svc_destroy` が無ければ、プロセスごと殺されている。`id_rotate` の `late_ms` が大きければ Doze でタイマーが遅れている (その間も前の ID で発信は続いているはず)
- 通知が消えていないか、アプリを最近の一覧から消すとどうなるか (`task_removed` の後に発信が続くか) も見る
- 両方の向き (Note10+ が発信 / S25 Ultra が発信) で行う。Samsung の省電力は機種と版で違う

## 3. 電池 (1 時間ずつ)

条件は 4 つ: 何もしない (アプリの常駐を止める) / 発信だけ / 発信 + LOW_POWER の受信 / 発信 + BALANCED の受信。

1. 測る端末を USB でつないだまま、条件を設定して適用し、統計を消す
   ```
   adb -s <serial> shell dumpsys battery | findstr level
   adb -s <serial> shell dumpsys batterystats --reset
   ```
2. **USB を抜く** (充電中は電池の統計が意味を持たない)。画面を消して 1 時間置く。もう 1 台は発信 ON で近く (1 m) に置く (受信の条件で、受け取る相手が居る状態にする)
3. 1 時間後に USB を挿して、すぐに取る
   ```
   adb -s <serial> shell dumpsys battery | findstr level
   adb -s <serial> shell dumpsys batterystats jp.wojak.blepoc > battery_<条件>.txt
   ```
   見る所: `Estimated power use (mAh)` の欄のこのアプリの uid の行、`Bluetooth` の欄 (スキャンの時間と回数)、`Wake lock`、電池の % の差
- S25 Ultra をワイヤレスデバッグでつないでいる時は、Wi-Fi の分だけ減りが増える。測る時間はワイヤレスデバッグを切り、終わってからつなぎ直す (`--reset` は抜く前に、取り出しはつなぎ直した後)
- 4 条件 × 2 台で 8 時間かかる。同じ端末で続けて測る時は、条件ごとに `--reset` からやり直す

## 4. ログの取り出しと集計

```
mkdir logs\note10 logs\s25u
adb -s RF8MB0KRY3Y pull /sdcard/Android/data/jp.wojak.blepoc/files/logs/ logs\note10\
adb -s <S25 の serial> pull /sdcard/Android/data/jp.wojak.blepoc/files/logs/ logs\s25u\
python analyze.py summary logs\note10\logs\blepoc_YYYYMMDD.csv logs\s25u\logs\blepoc_YYYYMMDD.csv
```

(`adb pull` はフォルダごと取ると `logs\note10\logs\` の下に入る。)

`analyze.py` (標準ライブラリだけ、Python 3.9 以上) の 4 つの使い方:

| コマンド | 出るもの |
|---|---|
| `summary <csv>...` | 行の種類ごとの件数、端末の対応の値、失敗の一覧 |
| `open <受信側>` | 画面を開いてから最初の受信までの秒数 (方式とモードごとの n・中央値・平均・90%・最小・最大)。開いて閉じるまでに 1 件も来なかった回数 |
| `latency <発信側> <受信側> [--offset-ms N]` | 発信側が新しい ID を出してから受信側が最初に受け取るまでの秒数。受信側の状態 (画面 on/off、前面/裏、モード) ごとにまとめる |
| `gaps <受信側> [--sender <発信側>] [--gap 30]` | 受信が N 秒を超えて途切れた区間、最後の受信、RSSI の中央値 |

ID の切り替えで MAC が変わるかは、受信側の CSV の `addr` の列を `rx_id` ごとに見る (`id_rotate` をまたいで同じアドレスが続いていないか)。

## 5. S25 Ultra に入れる

S25 Ultra はワイヤレスデバッグでつなぐ。ポートは毎回変わるので、**その時に白井さんが画面で読んで伝える** (推測でつながない)。PC と S25 Ultra は同じ Wi-Fi に居る必要がある。

1. S25 Ultra: 設定 → 開発者向けオプション → ワイヤレスデバッグ を ON
2. 初めての PC なら「ペアリングコードによるデバイスのペア設定」を開き、出た IP:ポート (ペア用) と 6 桁のコードで
   ```
   adb pair <IP>:<ペア用のポート> <6 桁のコード>
   ```
3. ワイヤレスデバッグの画面の上に出ている「IP アドレスとポート」(ペア用とは別のポート) で
   ```
   adb connect <IP>:<接続用のポート>
   adb devices -l
   ```
   一覧に出た名前 (`<IP>:<ポート>` か `adb-<serial>-xxxx._adb-tls-connect._tcp`) を以下の `<S25>` に使う
4. 入れて、許可を付けて、起動する
   ```
   adb -s <S25> install -r app-debug.apk
   adb -s <S25> shell pm grant jp.wojak.blepoc android.permission.BLUETOOTH_SCAN
   adb -s <S25> shell pm grant jp.wojak.blepoc android.permission.BLUETOOTH_ADVERTISE
   adb -s <S25> shell pm grant jp.wojak.blepoc android.permission.BLUETOOTH_CONNECT
   adb -s <S25> shell pm grant jp.wojak.blepoc android.permission.POST_NOTIFICATIONS
   adb -s <S25> shell pm grant jp.wojak.blepoc android.permission.NEARBY_WIFI_DEVICES
   adb -s <S25> shell am start -n jp.wojak.blepoc/.MainActivity
   adb -s <S25> logcat -d -s BlePoc
   ```
   logcat の `caps` の行に、端末の対応の値 (`multiAdv`、`extAdv`、`maxAdvLen`) が出る

## 確かめたこと (2026-11-07、Note10+ 1 台だけ)

- Galaxy Note10+ (SM-N975C、Android 12、API 31): `multiAdv=true`、`extAdv=true` (拡張広告に対応)、`maxAdvLen=1024`
- adb の extra で BLE (ServiceData) → BLE (manufacturer) → Nearby → 停止 を切り替えて、どれも `tx_start` と `rx_start` が成功した。ServiceData の 30 バイトの接続しない広告は `DATA_TOO_LARGE` にならずに始まった (相手の端末で受け取れるかは 2 台目が要るので未確認)。例外は出ていない
- 受信 (`rx`、`first_rx`) と画面オフでの動作は、2 台目が無いので試していない

## 分かっている限界

- 受信の一覧の「何秒前」は BLE の時だけ意味がある。Nearby は見つかった時と見失った時しか知らせないので、見えている間は「見えている」と出す
- 検出の速さの 1-b は 2 台の時計のずれを含む。1 秒より細かい差を比べる時は 1-a (1 台の中の時刻だけで測る) を使う
- `hb` は CPU が眠っている間は止まる (Handler)。発信が止まったかは、`hb` ではなく受信側の `rx` で判断する
- 送信の強さの `txPowerInEffect` (tx_start の detail) は端末が受け付けた段階 (0 = ULTRA_LOW 〜 3 = HIGH) で、dBm ではない
