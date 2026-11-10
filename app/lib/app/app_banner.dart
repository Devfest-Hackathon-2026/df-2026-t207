import 'dart:async';

import 'package:flutter/material.dart';

import 'app_palette.dart';

final _activeBanners = Expando<VoidCallback>();

/// 画面上部の通知を出す。新しい通知が来たら、表示中の通知を入れ替える。
VoidCallback? showAppBanner(
  BuildContext context,
  String message, {
  IconData icon = Icons.info_outline,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final overlay = Navigator.maybeOf(context, rootNavigator: true)?.overlay;
  if (overlay == null) return null;
  _activeBanners[overlay]?.call();

  late final OverlayEntry entry;
  void dismiss() {
    if (_activeBanners[overlay] != dismiss) return;
    _activeBanners[overlay] = null;
    entry.remove();
    entry.dispose();
  }

  entry = OverlayEntry(
    builder: (_) => AppBanner(
      title: message,
      icon: icon,
      actionLabel: actionLabel,
      onAction: onAction == null
          ? null
          : () {
              dismiss();
              onAction();
            },
      onDismiss: dismiss,
    ),
  );
  _activeBanners[overlay] = dismiss;
  overlay.insert(entry);
  return dismiss;
}

class AppBanner extends StatefulWidget {
  const AppBanner({
    super.key,
    required this.title,
    required this.icon,
    required this.onDismiss,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDismiss;

  @override
  State<AppBanner> createState() => _AppBannerState();
}

class _AppBannerState extends State<AppBanner> {
  Timer? _expiry;

  @override
  void initState() {
    super.initState();
    _expiry = Timer(const Duration(seconds: 6), widget.onDismiss);
  }

  @override
  void dispose() {
    _expiry?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.palette;
    final banner = Material(
      color: colors.canvas,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        child: Row(
          children: [
            Icon(widget.icon, color: colors.ink),
            const SizedBox(width: 8),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  widget.title,
                  style: TextStyle(
                    color: colors.ink,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            if (widget.actionLabel case final label?)
              TextButton(onPressed: widget.onAction, child: Text(label)),
            IconButton(
              tooltip: '通知を閉じる',
              onPressed: widget.onDismiss,
              icon: Icon(Icons.close, size: 20, color: colors.muted),
            ),
          ],
        ),
      ),
    );
    return Positioned(
      top: 0,
      left: 12,
      right: 12,
      child: SafeArea(
        bottom: false,
        minimum: const EdgeInsets.only(top: 8),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: MediaQuery.disableAnimationsOf(context)
                ? banner
                : TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    child: banner,
                    builder: (context, progress, child) =>
                        FractionalTranslation(
                          translation: Offset(0, progress - 1),
                          child: Opacity(opacity: progress, child: child),
                        ),
                  ),
          ),
        ),
      ),
    );
  }
}
