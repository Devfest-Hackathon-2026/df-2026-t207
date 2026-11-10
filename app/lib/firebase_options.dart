// Firebase の設定 (flutterfire configure と同じ形)。2026-11-08 に Firebase Management API から作った。
// ここのキーは公開が前提のクライアント用のキー。守りは Security Rules と、api・vision の ID トークンの検証 (docs/tech-decisions.md の 8 節)。
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    if (defaultTargetPlatform == TargetPlatform.android) return android;
    throw UnsupportedError('Android と Web だけ設定してある');
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDhwq4qou_QgZUhgLAUyv4yjN7P7tGNuXA',
    appId: '1:591807217114:web:012aa6b5d7d08c7f78d4e3',
    messagingSenderId: '591807217114',
    projectId: 'project-10522535-9db8-40c0-a68',
    authDomain: 'project-10522535-9db8-40c0-a68.firebaseapp.com',
    storageBucket: 'project-10522535-9db8-40c0-a68.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDERkGkXaXBxVRhi5R5uW9qUHuECKb2POY',
    appId: '1:591807217114:android:e942dd02a9f11d6378d4e3',
    messagingSenderId: '591807217114',
    projectId: 'project-10522535-9db8-40c0-a68',
    storageBucket: 'project-10522535-9db8-40c0-a68.firebasestorage.app',
  );
}
