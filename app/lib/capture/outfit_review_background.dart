import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';

const homeOutfitPhotoTag = 'today-outfit-photo';
const _photoSettledAt = 0.70;
const _photoMotion = Interval(0, _photoSettledAt, curve: Curves.easeInOutCubic);
const _reviewBackground = Color(0xff242424);

class HomeOutfitPhotoHero extends StatelessWidget {
  const HomeOutfitPhotoHero({
    super.key,
    required this.image,
    required this.alignment,
    required this.background,
    required this.shade,
  });

  final ImageProvider image;
  final Alignment alignment;
  final Color background;
  final Gradient shade;

  @override
  Widget build(BuildContext context) {
    final photo = _HomePhoto(
      image: image,
      alignment: alignment,
      background: background,
      shade: shade,
    );
    if (MediaQuery.disableAnimationsOf(context)) return photo;
    return Hero(
      tag: homeOutfitPhotoTag,
      curve: Curves.linear,
      createRectTween: (begin, end) =>
          _HomePhotoRectTween(begin: begin, end: end, opening: false),
      child: photo,
    );
  }
}

class _HomePhoto extends StatelessWidget {
  const _HomePhoto({
    required this.image,
    required this.alignment,
    required this.background,
    required this.shade,
  });

  final ImageProvider image;
  final Alignment alignment;
  final Color background;
  final Gradient shade;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      ColoredBox(color: background),
      Image(
        image: image,
        fit: BoxFit.cover,
        alignment: alignment,
        excludeFromSemantics: true,
      ),
      DecoratedBox(decoration: BoxDecoration(gradient: shade)),
    ],
  );
}

class _HomePhotoRectTween extends RectTween {
  _HomePhotoRectTween({super.begin, super.end, required this.opening});

  final bool opening;

  @override
  Rect? lerp(double t) => super.lerp(
    opening ? _photoMotion.transform(t) : 1 - _photoMotion.transform(1 - t),
  );
}

Widget _homePhotoFlight(
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext from,
  BuildContext to,
  Color background,
) {
  final home =
      (direction == HeroFlightDirection.push ? from : to).widget as Hero;
  final source = home.child as _HomePhoto;
  return FadeTransition(
    opacity: animation.drive(
      Tween(begin: 1.0, end: 0.0).chain(
        CurveTween(
          curve: const Interval(_photoSettledAt, 0.84, curve: Curves.easeInOut),
        ),
      ),
    ),
    child: AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final expansion = _photoMotion.transform(animation.value);
        return ClipRRect(
          borderRadius: BorderRadius.circular(16 * (1 - expansion)),
          child: _HomePhoto(
            image: source.image,
            alignment: Alignment.lerp(
              source.alignment,
              Alignment.center,
              expansion,
            )!,
            background: Color.lerp(source.background, background, expansion)!,
            shade: Gradient.lerp(source.shade, null, expansion)!,
          ),
        );
      },
    ),
  );
}

/// 撮影後の確認画面で使う、下部にかけてぼける背景。
class OutfitReviewBackground extends StatelessWidget {
  OutfitReviewBackground({super.key, required Uint8List photoBytes})
    : image = MemoryImage(photoBytes),
      heroTag = null,
      light = false,
      blurSigma = 10,
      showBottomShade = true;

  const OutfitReviewBackground.image({
    super.key,
    required this.image,
    this.heroTag,
    this.light = false,
    this.blurSigma = 10,
    this.showBottomShade = true,
  });

  final ImageProvider? image;
  final Object? heroTag;
  final bool light;
  final double blurSigma;
  final bool showBottomShade;

  @override
  Widget build(BuildContext context) {
    final provider = image;
    final surfaceColor = light ? Colors.white : _reviewBackground;
    final tag = MediaQuery.disableAnimationsOf(context) ? null : heroTag;
    final expandsFromHome = tag == homeOutfitPhotoTag && provider != null;
    final photo = ColoredBox(
      color: surfaceColor,
      child: provider == null
          ? null
          : Image(image: provider, fit: BoxFit.cover),
    );
    final background = Stack(
      fit: StackFit.expand,
      children: [
        if (tag != null && !expandsFromHome)
          Hero(tag: tag, child: photo)
        else
          photo,
        if (provider != null)
          ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.transparent, Colors.white],
              stops: [0, 0.48, 0.78],
            ).createShader(bounds),
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: blurSigma,
                sigmaY: blurSigma,
              ),
              child: Image(image: provider, fit: BoxFit.cover),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                light ? const Color(0x66ffffff) : const Color(0x33000000),
                Colors.transparent,
                if (showBottomShade)
                  light ? Colors.white : const Color(0xee181818),
              ],
              stops: showBottomShade ? const [0, 0.45, 1] : const [0, 0.45],
            ),
          ),
        ),
      ],
    );
    if (!expandsFromHome) return background;

    final routeAnimation = ModalRoute.of(context)?.animation;
    return Hero(
      tag: homeOutfitPhotoTag,
      curve: Curves.linear,
      createRectTween: (begin, end) =>
          _HomePhotoRectTween(begin: begin, end: end, opening: true),
      flightShuttleBuilder: (_, animation, direction, from, to) =>
          _homePhotoFlight(animation, direction, from, to, surfaceColor),
      placeholderBuilder: (context, size, child) => SizedBox.fromSize(
        size: size,
        child: routeAnimation == null
            ? child
            : FadeTransition(
                opacity: routeAnimation.drive(
                  CurveTween(curve: const Interval(0.63, _photoSettledAt)),
                ),
                child: child,
              ),
      ),
      child: background,
    );
  }
}
