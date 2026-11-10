import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../auth/first_outfit_screen.dart';
import '../auth/login_screen.dart';
import '../auth/name_setup_route.dart';
import '../ble/ble_controller.dart';
import '../capture/outfit_camera_screen.dart';
import '../capture/outfit_submission.dart';
import '../register/outfit_job.dart';
import '../services/auth_service.dart';
import 'app_banner.dart';
import 'app_loading.dart';
import 'app_page_transitions.dart';
import 'app_palette.dart';
import 'main_shell.dart';
import 'web_stage.dart';

/// アプリ全体。ログインの状態で、ログイン画面と本体 (下のメニューの土台) を切り替える。
class DfHackApp extends StatefulWidget {
  const DfHackApp({
    super.key,
    required this.auth,
    required this.api,
    required this.ble,
    this.initialDarkMode = false,
    this.onSaveDarkMode,
    this.jobs,
  });

  final AuthService auth;
  final ApiClient api;
  final BleController ble;
  final bool initialDarkMode;
  final Future<void> Function(bool)? onSaveDarkMode;
  final OutfitJobSource? jobs;

  @override
  State<DfHackApp> createState() => _DfHackAppState();
}

class _DfHackAppState extends State<DfHackApp> {
  late bool _darkMode = widget.initialDarkMode;

  Future<void> _setDarkMode(bool enabled) async {
    await widget.onSaveDarkMode?.call(enabled);
    if (mounted) setState(() => _darkMode = enabled);
  }

  ThemeData _theme(Brightness brightness) => ThemeData(
    colorSchemeSeed: const Color(0xff141414),
    brightness: brightness,
    scaffoldBackgroundColor: AppPalette(brightness).canvas,
    filledButtonTheme: const FilledButtonThemeData(style: _actionStyle),
    outlinedButtonTheme: const OutlinedButtonThemeData(style: _actionStyle),
    elevatedButtonTheme: const ElevatedButtonThemeData(style: _actionStyle),
    textButtonTheme: const TextButtonThemeData(style: _actionStyle),
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        for (final platform in TargetPlatform.values)
          platform: const AppPageTransitionsBuilder(),
      },
    ),
  );

  static const _actionStyle = ButtonStyle(
    shape: WidgetStatePropertyAll(appActionShape),
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WEARBY',
      // PC のブラウザ (Web デモ) で、マウスのドラッグでも横・縦にめくれるようにする (Flutter の既定はタッチだけ)
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: PointerDeviceKind.values.toSet(),
      ),
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: _darkMode ? ThemeMode.dark : ThemeMode.light,
      themeAnimationDuration: Duration.zero,
      builder: (context, child) => WebStage(
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: context.palette.systemOverlays,
          child: child!,
        ),
      ),
      home: AppRoot(
        auth: widget.auth,
        api: widget.api,
        ble: widget.ble,
        onDarkModeChanged: _setDarkMode,
        jobs: widget.jobs,
      ),
    );
  }
}

/// 初回: ログイン → 名前 → 最初のコーデの案内 → 本体 (spec.md の 2 節)。
/// Web デモはログイン画面を出さず、匿名で本体に入る。
class AppRoot extends StatefulWidget {
  const AppRoot({
    super.key,
    required this.auth,
    required this.api,
    required this.ble,
    required this.onDarkModeChanged,
    this.jobs,
  });

  final AuthService auth;
  final ApiClient api;
  final BleController ble;
  final Future<void> Function(bool) onDarkModeChanged;
  final OutfitJobSource? jobs;

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  late final _submission = OutfitSubmission(widget.api, jobs: widget.jobs);

  /// ログインの直後、名前があるかを確かめている間と、初回の案内の間は本体を出さない。
  bool _onboarding = false;
  bool _restoringSession = false;
  bool _anonymousSignInFailed = false;
  bool _anonymousSignInPending = false;

  @override
  void initState() {
    super.initState();
    widget.auth.addListener(_onAuthChanged);
    if (kIsWeb) {
      if (!widget.auth.isSignedIn) _signInAnonymously();
    } else if (widget.auth.isSignedIn) {
      _restoringSession = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _restoreSession();
      });
    }
  }

  @override
  void dispose() {
    widget.auth.removeListener(_onAuthChanged);
    _submission.dispose();
    super.dispose();
  }

  void _onAuthChanged() {
    if (!widget.auth.isSignedIn) _submission.clear(forget: false);
    if (mounted) setState(() {});
  }

  Future<void> _signInAnonymously() async {
    setState(() {
      _anonymousSignInFailed = false;
      _anonymousSignInPending = true;
    });
    try {
      await widget.auth.signInAnonymously();
    } catch (_) {
      if (mounted) setState(() => _anonymousSignInFailed = true);
    } finally {
      if (mounted) setState(() => _anonymousSignInPending = false);
    }
  }

  Future<void> _restoreSession() async {
    try {
      await _signIn();
    } catch (_) {
      if (mounted) {
        showAppBanner(context, 'ログイン状態を確認できませんでした', icon: Icons.error_outline);
      }
    } finally {
      if (mounted) setState(() => _restoringSession = false);
    }
  }

  Future<void> _signIn() => _signInWith(widget.auth.signInWithGoogle);

  /// 審査用アカウント (メールとパスワード)。ログインの後は Google と同じ流れ (名前 → 最初のコーデの案内)。
  Future<void> _signInTest(String email, String password) =>
      _signInWith(() => widget.auth.signInWithEmail(email, password));

  Future<void> _signInWith(Future<void> Function() signIn) async {
    setState(() => _onboarding = true);
    try {
      if (!widget.auth.isSignedIn) await signIn();
      final me = await widget.api.getMe();
      if (!mounted) return;
      if (me.displayName.isEmpty) {
        await Navigator.of(context).push(nameSetupRoute(onContinue: _saveName));
        return;
      }
      setState(() => _onboarding = false);
    } catch (_) {
      // 自分の状態が取れなければ、ログインごとやり直す
      try {
        if (widget.auth.isSignedIn) await widget.auth.signOut();
      } finally {
        if (mounted) setState(() => _onboarding = false);
      }
      rethrow;
    }
  }

  Future<void> _saveName(String name) async {
    final me = await widget.api.updateDisplayName(name);
    if (!mounted) return;
    await Navigator.of(context).push(
      firstOutfitRoute(
        displayName: name,
        onLater: _finishOnboarding,
        onRecord: () async {
          var submitted = false;
          await Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => OutfitCameraScreen(
                onPhotoConfirmed: (photo) async {
                  final bytes = await photo.readAsBytes();
                  if (!mounted || !widget.auth.isSignedIn) return;
                  await _submission.start(me.uid, bytes);
                  submitted = true;
                },
              ),
            ),
          );
          if (mounted && submitted) _finishOnboarding();
        },
      ),
    );
  }

  void _finishOnboarding() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() => _onboarding = false);
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = widget.auth.isSignedIn;
    if (_restoringSession || _anonymousSignInPending) {
      return const AppLoadingScreen();
    }
    if (!signedIn && kIsWeb) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_anonymousSignInFailed ? 'ログインできませんでした' : 'ログアウトしました'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _signInAnonymously,
                child: Text(_anonymousSignInFailed ? 'もう一度試す' : 'デモを開く'),
              ),
            ],
          ),
        ),
      );
    }
    if (!signedIn || _onboarding) {
      return LoginScreen(onGoogleSignIn: _signIn, onTestSignIn: _signInTest);
    }
    return MainShell(
      auth: widget.auth,
      api: widget.api,
      ble: widget.ble,
      submission: _submission,
      onDarkModeChanged: widget.onDarkModeChanged,
    );
  }
}
