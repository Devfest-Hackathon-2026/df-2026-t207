import 'package:app/services/auth_service.dart';

/// Firebase への接続なしで画面をテストするための実装。
class DevAuthService extends AuthService {
  bool _signedIn = false;

  @override
  bool get isSignedIn => _signedIn;

  @override
  Future<String?> idToken() async => _signedIn ? 'dev-token' : null;

  @override
  Future<void> signInWithGoogle() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _signedIn = true;
    notifyListeners();
  }

  @override
  Future<void> signInWithEmail(String email, String password) async {
    _signedIn = true;
    notifyListeners();
  }

  @override
  Future<void> signInAnonymously() async {
    _signedIn = true;
    notifyListeners();
  }

  @override
  Future<void> signOut() async {
    _signedIn = false;
    notifyListeners();
  }
}
