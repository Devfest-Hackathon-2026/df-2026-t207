import 'package:flutter/material.dart';

class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  static const duration = Duration(milliseconds: 260);

  @override
  Duration get transitionDuration => duration;

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 220);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => centerFadeTransition(context, animation, child);
}

Widget centerFadeTransition(
  BuildContext context,
  Animation<double> animation,
  Widget child, {
  double initialOpacity = 0,
}) {
  if (MediaQuery.disableAnimationsOf(context)) return child;
  final progress = animation.drive(CurveTween(curve: Curves.easeOutCubic));
  return FadeTransition(
    opacity: progress.drive(Tween(begin: initialOpacity, end: 1.0)),
    child: ScaleTransition(
      scale: progress.drive(Tween(begin: 0.97, end: 1.0)),
      child: child,
    ),
  );
}
