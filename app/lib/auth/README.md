# ログイン画面

`LoginScreen` は Android のログイン画面です。Google 認証の処理をコールバックとして受け取ります。認証エラーは例外として返すと画面で再試行できます。Web デモではこの画面を使わず、匿名のデモ入口を表示します。

Flutter の骨組みを作成したら、`pubspec.yaml` の `flutter:` に以下の素材を登録してください。

```yaml
  assets:
    - assets/images/login_illustration.png
    - assets/images/first_outfit_illustration.png
```

背景は AI が生成した架空の人物のイラストです。Firebase の設定、認証処理と各リンク先は接続側で指定します。

ログイン成功後の名前入力には `nameSetupRoute` を使えます。共通の背景を保ちながらフェードで切り替わり、アニメーションを減らす設定にも対応します。`onContinue` に名前の保存と次画面への遷移を渡してください。名前は API の `PATCH /v1/me` に合わせ、空欄を受け付けず 20 文字以内にしています。プレビューの仮遷移は認証や保存を行いません。

テスト用の名前を表示する場合は、`nameSetupRoute` に `initialName` を渡せます。省略すると空欄で始まります。

初回の名前設定後は `firstOutfitRoute` に名前を渡して、最初のコーデ登録を案内できます。`onRecord` は撮影画面を差し替えます。`onLater` を省略すると未登録状態のホームへ進み、指定した場合はその処理を呼びます。初回かどうかの判定、名前の保存、ホームのデータや未接続の操作はアプリの骨組み側で実装します。背景は AI 生成のイラストです。

`onRecord` を省略すると「コーデを投稿する」でアプリ内のカメラを開きます。シャッターを押すと同じルートで `OutfitPhotoReviewScreen` に切り替わり、「投稿」または撮りなおしを選べます。投稿処理は `onPhotoConfirmed` に接続します。音声は使いません。

投稿前にアプリで `jobId` を作り、Firestore の購読を始めてから、JPEG と `jobId` を画像処理サービスへ送ります。処理状況はアプリ内の通知に表示し、ユーザーが結果を確認した後に `PUT /v1/outfits/today` で登録します。公開はマイページから設定します。
