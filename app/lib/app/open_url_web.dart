import 'package:web/web.dart' as web;

/// 新しいタブで開く (Web デモの帯から APK を落とす)。
void openUrl(String url) => web.window.open(url, '_blank');
