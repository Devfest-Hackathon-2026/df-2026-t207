import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../auth/auth_background.dart';
import '../capture/outfit_review_background.dart';

class OutfitCapturePrompt extends StatelessWidget {
  const OutfitCapturePrompt({
    super.key,
    required this.onCapturePressed,
    this.embedded = false,
    this.collapse = 0,
    this.outfitToPublish,
  });

  final VoidCallback? onCapturePressed;
  final bool embedded;
  final double collapse;
  final ImageProvider? outfitToPublish;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      if (outfitToPublish case final photo?)
        OutfitReviewBackground.image(image: photo)
      else
        AuthBackground(
          assetPath: 'assets/images/nearby_capture_illustration.png',
          blurStart: embedded ? 0.48 : 0.64,
          blurEnd: embedded ? 0.78 : 0.86,
          alignment: embedded
              ? Alignment.lerp(
                  const Alignment(0, -0.62),
                  const Alignment(0, -0.34),
                  collapse,
                )!
              : Alignment.center,
        ),
      if (!embedded)
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 104,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x59000000), Colors.transparent],
              ),
            ),
          ),
        ),
      SafeArea(
        top: !embedded,
        bottom: !embedded,
        left: !embedded,
        right: !embedded,
        child: Align(
          alignment: embedded
              ? Alignment(0, 1 - collapse)
              : Alignment.bottomCenter,
          child: SingleChildScrollView(
            primary: false,
            padding: embedded
                ? EdgeInsets.lerp(
                    const EdgeInsets.fromLTRB(16, 16, 16, 10),
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    collapse,
                  )!
                : const EdgeInsets.fromLTRB(24, 20, 24, 48),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final buttonWidth = embedded
                    ? lerpDouble(56, 48, collapse)!
                    : 72.0;
                const gap = 14.0;
                final shortTitle = embedded && collapse >= 0.55;
                final title = outfitToPublish != null
                    ? 'コーデを公開して、\nみんなのを見よう。'
                    : shortTitle
                    ? 'コーデを投稿しよう'
                    : 'コーデを投稿して、\nみんなのを見よう。';
                const heightBehavior = TextHeightBehavior(
                  applyHeightToLastDescent: false,
                );
                final copyWidth = constraints.maxWidth - buttonWidth - gap;
                final titleSize = (copyWidth / 10).clamp(
                  embedded ? lerpDouble(17, 12, collapse)! : 17.0,
                  embedded ? lerpDouble(23, 16, collapse)! : 28.0,
                );
                final titleStyle = TextStyle(
                  color: Colors.white,
                  fontSize: titleSize,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                  height: 1.21,
                );
                final copy = Text(
                  title,
                  key: ValueKey(title),
                  style: titleStyle,
                  textHeightBehavior: heightBehavior,
                );
                double extraHeight = 0;
                double buttonInset = 0;
                if (!embedded) {
                  final measure = TextPainter(
                    text: TextSpan(
                      text: title,
                      style: DefaultTextStyle.of(context).style
                          .merge(titleStyle),
                    ),
                    textDirection: Directionality.of(context),
                    textScaler: MediaQuery.textScalerOf(context),
                    locale: Localizations.maybeLocaleOf(context),
                    textHeightBehavior: heightBehavior,
                  )..layout(maxWidth: copyWidth.clamp(0.0, double.infinity));
                  extraHeight = measure.height;
                  final lastBaseline = measure
                      .computeLineMetrics()
                      .last
                      .baseline;
                  buttonInset = (measure.height - lastBaseline) * 2 + 2;
                  measure.dispose();
                }
                return Row(
                  crossAxisAlignment: embedded
                      ? CrossAxisAlignment.center
                      : CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: embedded
                          ? AnimatedSwitcher(
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 180),
                              layoutBuilder: (current, previous) => Stack(
                                alignment: Alignment.centerLeft,
                                children: [...previous, ?current],
                              ),
                              child: copy,
                            )
                          : Padding(
                              padding: EdgeInsets.only(top: extraHeight),
                              child: Transform.scale(
                                scaleY: 2,
                                alignment: Alignment.bottomLeft,
                                child: copy,
                              ),
                            ),
                    ),
                    const SizedBox(width: gap),
                    Padding(
                      padding: EdgeInsets.only(bottom: buttonInset),
                      child: Semantics(
                        label: outfitToPublish == null ? '撮影する' : '公開する',
                        child: FilledButton(
                          onPressed: onCapturePressed,
                          style: FilledButton.styleFrom(
                            minimumSize: Size(buttonWidth, buttonWidth),
                            padding: const EdgeInsets.all(10),
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xff242424),
                          ),
                          child: Icon(
                            Icons.chevron_right,
                            size: embedded ? lerpDouble(27, 24, collapse) : 34,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ],
  );
}
