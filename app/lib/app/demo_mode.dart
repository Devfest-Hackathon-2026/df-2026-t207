import 'package:flutter/foundation.dart';

/// デモモード: 近くの人の検出 (BLE) の代わりに、AI 生成のデモの人物を出す (`POST /v1/demo/nearby`)。
/// 審査員はスマホ 1 台でも試せ、2 台で本物のすれ違いを見せる時は設定で切る。
/// 初めの値は build の `MOCK_NEARBY` (配る APK は true)。Android は設定で切り替えて端末に残す。Web は常にデモ。
final demoMode = ValueNotifier<bool>(const bool.fromEnvironment('MOCK_NEARBY'));
