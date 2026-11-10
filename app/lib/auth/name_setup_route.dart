import 'package:flutter/material.dart';

import 'name_setup_screen.dart';

/// 背景を保ちながら、ログイン画面から名前設定へ切り替える。
Route<void> nameSetupRoute({
  required Future<void> Function(String name) onContinue,
  String initialName = '',
}) {
  return PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (context, animation, secondaryAnimation) =>
        NameSetupScreen(onContinue: onContinue, initialName: initialName),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.disableAnimationsOf(context)) return child;
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
        child: child,
      );
    },
  );
}
