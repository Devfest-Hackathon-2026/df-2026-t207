import 'package:flutter/material.dart';

import '../app/app_loading.dart';
import 'auth_background.dart';
import 'auth_layout.dart';

/// Android のログイン画面。認証は呼び出し元から渡す。
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.onGoogleSignIn,
    this.onTestSignIn,
  });

  final Future<void> Function() onGoogleSignIn;

  /// 審査用アカウント (メールとパスワード) でのログイン。渡された時だけ入口を出す。
  final Future<void> Function(String email, String password)? onTestSignIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _loading = false;
  bool _failed = false;

  Future<void> _signIn() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      await widget.onGoogleSignIn();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openTestSignIn() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: const Color(0xff282824),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => _TestSignInSheet(onSignIn: widget.onTestSignIn!),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff282824),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AuthBackground(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (constraints.maxHeight - 48).clamp(
                      0,
                      double.infinity,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: (constraints.maxHeight * 0.63 - 24).clamp(
                          0,
                          double.infinity,
                        ),
                      ),
                      const Text(
                        'コーデから、つながろう。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          height: 1.35,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: authSubtitleMinHeight,
                        ),
                        child: const Text(
                          '近くのコーデを楽しもう',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                      SizedBox(height: authActionGap(constraints.maxHeight)),
                      SizedBox(
                        height: 48,
                        child: FilledButton(
                          onPressed: _loading ? null : _signIn,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xff222222),
                          ),
                          child: _loading
                              ? const AppLoadingIndicator()
                              : const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'G',
                                      style: TextStyle(
                                        color: Color(0xff4285f4),
                                        fontSize: 21,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Flexible(
                                      child: Text(
                                        'Google で続ける',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      SizedBox(
                        height: 48,
                        child: Center(
                          child: _failed
                              ? const Text(
                                  'ログインできませんでした。もう一度お試しください。',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                  ),
                                  textAlign: TextAlign.center,
                                )
                              : null,
                        ),
                      ),
                      if (widget.onTestSignIn != null)
                        TextButton(
                          onPressed: _loading ? null : _openTestSignIn,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('審査用アカウントでログイン'),
                        ),
                      const SizedBox(height: 24),
                      const Text(
                        '@Team Wojak',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 審査用アカウントのメールとパスワードを入れる。成功したらシートを閉じ、ログインの後の流れは呼び出し元が進める。
class _TestSignInSheet extends StatefulWidget {
  const _TestSignInSheet({required this.onSignIn});

  final Future<void> Function(String email, String password) onSignIn;

  @override
  State<_TestSignInSheet> createState() => _TestSignInSheetState();
}

class _TestSignInSheetState extends State<_TestSignInSheet> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _failed = false;
  bool _showPassword = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      await widget.onSignIn(_email.text.trim(), _password.text);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xff92928c)),
    );
    InputDecoration fieldDecoration(String label) => InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xffd1d1cc)),
      floatingLabelStyle: const TextStyle(color: Colors.white),
      filled: true,
      fillColor: const Color(0xff343430),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      enabledBorder: border,
      disabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: Colors.white, width: 2),
      ),
    );

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          12,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: AutofillGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xff92928c),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '審査用アカウント',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: '閉じる',
                    color: Colors.white,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _email,
                enabled: !_loading,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [
                  AutofillHints.username,
                  AutofillHints.email,
                ],
                style: const TextStyle(color: Colors.white),
                cursorColor: Colors.white,
                decoration: fieldDecoration('メールアドレス'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _password,
                enabled: !_loading,
                obscureText: !_showPassword,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                style: const TextStyle(color: Colors.white),
                cursorColor: Colors.white,
                decoration: fieldDecoration('パスワード').copyWith(
                  suffixIcon: IconButton(
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                    tooltip: _showPassword ? 'パスワードを隠す' : 'パスワードを表示',
                    color: Colors.white70,
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
              if (_failed) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: const Text(
                    'ログインできませんでした。入力内容と通信を確認してください',
                    style: TextStyle(color: Color(0xffffc5b9), fontSize: 13),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _loading ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xff222222),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _loading
                      ? const AppLoadingIndicator(color: Color(0xff222222))
                      : const Text(
                          'ログイン',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
