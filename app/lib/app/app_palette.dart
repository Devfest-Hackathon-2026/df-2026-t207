import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const appActionShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(8)),
);

extension AppPaletteContext on BuildContext {
  AppPalette get palette => AppPalette(Theme.of(this).brightness);
}

class AppPalette {
  const AppPalette(this.brightness);

  final Brightness brightness;
  bool get isDark => brightness == Brightness.dark;

  Color get canvas => isDark ? const Color(0xff1c1c1a) : Colors.white;
  Color get loadingBackground => isDark ? const Color(0xff282826) : canvas;
  Color get panel => isDark ? const Color(0xff272725) : const Color(0xfff7f6f4);
  Color get control =>
      isDark ? const Color(0xff333330) : const Color(0xfff4f3f1);
  Color get outline =>
      isDark ? const Color(0xff4d4d48) : const Color(0xffeae8e5);
  Color get ink => isDark ? const Color(0xfff7f6f4) : const Color(0xff232321);
  Color get muted => isDark ? const Color(0xffbdbdb6) : const Color(0xff646460);
  Color get danger =>
      isDark ? const Color(0xffffa9a4) : const Color(0xffb3261e);

  SystemUiOverlayStyle get systemOverlays {
    final icons = isDark ? Brightness.light : Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: brightness,
      statusBarIconBrightness: icons,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: icons,
    );
  }
}
