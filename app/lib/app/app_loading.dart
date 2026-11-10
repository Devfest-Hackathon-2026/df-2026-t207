import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_palette.dart';

class AppRefreshIndicator extends StatelessWidget {
  const AppRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  final RefreshCallback onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: onRefresh,
    color: context.palette.ink,
    backgroundColor: context.palette.control,
    child: child,
  );
}

class AppLoadingScreen extends StatelessWidget {
  const AppLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.palette;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: colors.systemOverlays,
      child: Scaffold(
        backgroundColor: colors.loadingBackground,
        body: Center(
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              CustomPaint(
                size: const Size.square(96),
                painter: _HangerPainter(color: colors.ink),
              ),
              const Positioned(
                bottom: -20,
                child: AppLoadingIndicator(size: 32),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RipplingHanger extends StatefulWidget {
  const RipplingHanger({super.key, required this.center, required this.color});

  final Offset center;
  final Color color;

  @override
  State<RipplingHanger> createState() => _RipplingHangerState();
}

class _RipplingHangerState extends State<RipplingHanger>
    with SingleTickerProviderStateMixin {
  late final _phase = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _phase.reset();
    } else if (!_phase.isAnimating) {
      _phase.repeat();
    }
  }

  @override
  void dispose() {
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _HangerPainter(
        phase: _phase,
        center: widget.center,
        color: widget.color,
      ),
    ),
  );
}

class AppLoadingIndicator extends StatefulWidget {
  const AppLoadingIndicator({super.key, this.color, this.size = 26});

  final Color? color;
  final double size;

  @override
  State<AppLoadingIndicator> createState() => _AppLoadingIndicatorState();
}

class _AppLoadingIndicatorState extends State<AppLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final _phase = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _phase.reset();
    } else if (!_phase.isAnimating) {
      _phase.repeat();
    }
  }

  @override
  void dispose() {
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '読み込み中',
      child: CustomPaint(
        size: Size(widget.size, widget.size / 2),
        painter: _LoadingDotsPainter(
          _phase,
          widget.color ?? context.palette.ink,
        ),
      ),
    );
  }
}

class _LoadingDotsPainter extends CustomPainter {
  _LoadingDotsPainter(this.phase, this.color) : super(repaint: phase);

  final Animation<double> phase;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (var index = 0; index < 3; index++) {
      final pulse = (1 + math.cos((phase.value - index / 6) * 2 * math.pi)) / 2;
      paint.color = color.withValues(alpha: 0.35 + 0.65 * pulse);
      canvas.drawCircle(
        Offset(
          size.width * (index + 1) / 4,
          size.height * (0.58 - 0.16 * pulse),
        ),
        size.width / 13,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_LoadingDotsPainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.color != color;
}

class _HangerPainter extends CustomPainter {
  const _HangerPainter({this.phase, this.center, required this.color})
    : super(repaint: phase);

  final Animation<double>? phase;
  final Offset? center;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final motion = phase;
    final origin = center ?? size.center(Offset.zero);
    if (motion != null) {
      final maxRadius = Offset(
        math.max(origin.dx, size.width - origin.dx),
        math.max(origin.dy, size.height - origin.dy),
      ).distance;
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.25;
      for (var index = 0; index < 3; index++) {
        final progress = (motion.value + index / 3) % 1;
        ring.color = color.withValues(
          alpha: 0.28 * math.sin(progress * math.pi),
        );
        canvas.drawCircle(origin, 32 + progress * (maxRadius - 32), ring);
      }
    }

    canvas.save();
    canvas.translate(origin.dx - 48, origin.dy - 48);
    if (motion != null) {
      canvas.translate(48, 27);
      canvas.rotate(math.sin(motion.value * 2 * math.pi) * 0.13);
      canvas.translate(-48, -27);
    }
    // Android の startup_hanger.xml と同じ位置・輪郭にする。
    final hanger = Path()
      ..moveTo(38, 35)
      ..cubicTo(38, 29, 42, 25, 48, 25)
      ..cubicTo(54, 25, 58, 29, 58, 34)
      ..cubicTo(58, 38, 55, 41, 50, 44)
      ..quadraticBezierTo(48, 46, 48, 49)
      ..lineTo(77, 64)
      ..quadraticBezierTo(83, 67, 81, 72)
      ..quadraticBezierTo(80, 75, 75, 75)
      ..lineTo(21, 75)
      ..quadraticBezierTo(16, 75, 15, 72)
      ..quadraticBezierTo(13, 67, 19, 64)
      ..lineTo(48, 49);
    canvas.drawPath(
      hanger,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HangerPainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.center != center ||
      oldDelegate.color != color;
}
