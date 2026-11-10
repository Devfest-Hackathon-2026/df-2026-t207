import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../app/app_banner.dart';
import '../app/app_loading.dart';
import '../app/app_palette.dart';
import '../capture/outfit_camera_screen.dart';
import '../home/home_screen.dart';
import 'auth_background.dart';
import 'auth_layout.dart';

/// 初回のコーデ登録への入口。各ボタンの遷移は呼び出し元が指定する。
class FirstOutfitScreen extends StatefulWidget {
  const FirstOutfitScreen({
    super.key,
    required this.displayName,
    this.onRecord,
    this.onPhotoConfirmed,
    this.onLater,
  });

  final String displayName;

  /// 指定した場合は撮影の代わりに呼ぶ（プレビューやテスト用）。
  final VoidCallback? onRecord;

  /// 写真確認画面で「投稿」を押したときの処理。
  final Future<void> Function(XFile photo)? onPhotoConfirmed;
  final VoidCallback? onLater;

  @override
  State<FirstOutfitScreen> createState() => _FirstOutfitScreenState();
}

class _FirstOutfitScreenState extends State<FirstOutfitScreen> {
  bool _openingCamera = false;

  Future<void> _record() async {
    if (_openingCamera) return;
    if (widget.onRecord != null) {
      widget.onRecord!();
      return;
    }
    setState(() => _openingCamera = true);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) =>
              OutfitCameraScreen(onPhotoConfirmed: widget.onPhotoConfirmed),
        ),
      );
    } catch (_) {
      if (mounted) {
        showAppBanner(
          context,
          'カメラを開けませんでした。もう一度お試しください',
          icon: Icons.error_outline,
        );
      }
    } finally {
      if (mounted) setState(() => _openingCamera = false);
    }
  }

  void _goHome() {
    if (widget.onLater != null) {
      widget.onLater!();
      return;
    }
    final onPhotoConfirmed = widget.onPhotoConfirmed;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (homeContext) {
          void unavailable() {
            showAppBanner(homeContext, 'まだ利用できません');
          }

          Future<void> capture() async {
            try {
              await Navigator.of(homeContext).push<void>(
                MaterialPageRoute(
                  builder: (_) =>
                      OutfitCameraScreen(onPhotoConfirmed: onPhotoConfirmed),
                ),
              );
            } catch (_) {
              if (homeContext.mounted) {
                showAppBanner(
                  homeContext,
                  'カメラを開けませんでした。もう一度お試しください',
                  icon: Icons.error_outline,
                );
              }
            }
          }

          return HomeScreen(
            hasTodayOutfit: false,
            isPublishing: false,
            viewCountToday: 0,
            items: const [],
            onCapturePressed: capture,
            onItemsPressed: unavailable,
            onPublishPressed: unavailable,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff282824),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AuthBackground(
            assetPath: 'assets/images/first_outfit_illustration.png',
          ),
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
                      Text(
                        '${widget.displayName}さん、こんにちは',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
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
                          '最初のコーデを投稿しよう',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      SizedBox(height: authActionGap(constraints.maxHeight)),
                      SizedBox(
                        height: 48,
                        child: FilledButton(
                          onPressed: _openingCamera ? null : _record,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xff222222),
                          ),
                          child: const Text(
                            'コーデを投稿する',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _goHome,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('後にする'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_openingCamera)
            ColoredBox(
              color: context.palette.loadingBackground,
              child: const Center(child: AppLoadingIndicator()),
            ),
        ],
      ),
    );
  }
}

Route<void> firstOutfitRoute({
  required String displayName,
  VoidCallback? onRecord,
  Future<void> Function(XFile photo)? onPhotoConfirmed,
  VoidCallback? onLater,
}) {
  return PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (context, animation, secondaryAnimation) => FirstOutfitScreen(
      displayName: displayName,
      onRecord: onRecord,
      onPhotoConfirmed: onPhotoConfirmed,
      onLater: onLater,
    ),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.disableAnimationsOf(context)) return child;
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
        child: child,
      );
    },
  );
}
