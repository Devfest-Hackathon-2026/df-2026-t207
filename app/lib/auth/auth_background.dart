import 'dart:ui';

import 'package:flutter/material.dart';

/// 初回画面で共通して使う背景。
class AuthBackground extends StatelessWidget {
  const AuthBackground({
    super.key,
    this.assetPath = 'assets/images/login_illustration.png',
    this.blurStart = 0.48,
    this.blurEnd = 0.78,
    this.alignment = Alignment.center,
  });

  final String assetPath;
  final double blurStart;
  final double blurEnd;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(assetPath, fit: BoxFit.cover, alignment: alignment),
        ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [
              Colors.transparent,
              Colors.transparent,
              Colors.white,
            ],
            stops: [0, blurStart, blurEnd],
          ).createShader(bounds),
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Image.asset(
              assetPath,
              fit: BoxFit.cover,
              alignment: alignment,
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Color(0x33000000),
                Color(0xee181818),
              ],
              stops: [0.35, 0.62, 1],
            ),
          ),
        ),
      ],
    );
  }
}
