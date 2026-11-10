import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'auth_service.dart';

/// Firebase Auth を使うログイン。Android は Google、Web デモは匿名。
///
/// api と vision はここの ID トークンを検証する。
class FirebaseAuthService extends AuthService {
  FirebaseAuthService._(this._auth) {
    _sub = _auth.authStateChanges().listen((_) => notifyListeners());
  }

  /// Web 用の OAuth クライアント ID。Android の Google ログインで、Firebase に通る ID トークンを取るのに使う。
  static const serverClientId =
      '591807217114-vu8a5te2n93limhj8nlu97cr9vllevpn.apps.googleusercontent.com';

  /// 前回のログインが戻るのを待ってから返す (待たないと Web で毎回新しい匿名の人になる)。
  static Future<FirebaseAuthService> create() async {
    final auth = FirebaseAuth.instance;
    await auth.authStateChanges().first;
    return FirebaseAuthService._(auth);
  }

  final FirebaseAuth _auth;
  late final StreamSubscription<User?> _sub;
  Future<void>? _googleReady;

  @override
  bool get isSignedIn => _auth.currentUser != null;

  @override
  Future<String?> idToken() async => _auth.currentUser?.getIdToken();

  @override
  Future<void> signInWithGoogle() async {
    final google = GoogleSignIn.instance;
    await (_googleReady ??= google.initialize(serverClientId: serverClientId));
    final account = await google.authenticate();
    final token = account.authentication.idToken;
    if (token == null) throw StateError('Google の ID トークンが取れなかった');
    await _auth.signInWithCredential(
      GoogleAuthProvider.credential(idToken: token),
    );
  }

  @override
  Future<void> signInWithEmail(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email, password: password);

  @override
  Future<void> signInAnonymously() async {
    if (isSignedIn) return;
    await _auth.signInAnonymously();
  }

  @override
  Future<void> signOut() async {
    if (!kIsWeb && _googleReady != null) {
      await GoogleSignIn.instance.signOut();
    }
    await _auth.signOut();
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
