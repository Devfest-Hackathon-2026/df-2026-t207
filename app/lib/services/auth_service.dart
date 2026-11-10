import 'package:flutter/foundation.dart';

/// ログインの窓口。画面はこれだけを見る。
///
/// Android は Google ログイン、Web デモは匿名ログイン。
abstract class AuthService extends ChangeNotifier {
  bool get isSignedIn;

  /// API に付ける ID トークン。ログインしていなければ null。
  Future<String?> idToken();

  /// Android の「Google で続ける」。失敗したら例外を投げる (画面が再試行を出す)。
  Future<void> signInWithGoogle();

  /// 審査用アカウント (メールとパスワード)。運営の「ソーシャルログインに頼らない審査の入口を」に合わせる。
  Future<void> signInWithEmail(String email, String password);

  /// Web デモの入口 (S16)。匿名で入る。
  Future<void> signInAnonymously();

  Future<void> signOut();
}
