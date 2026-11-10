import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/settings/settings_screen.dart';

Widget _settings({ValueNotifier<bool>? demoMode}) => MaterialApp(
  home: SettingsScreen(
    displayName: 'りお',
    photo: null,
    isPublishing: false,
    onSaveName: (_) async {},
    onSavePhoto: (_) async {},
    onLogout: () async {},
    onDarkModeChanged: (_) async {},
    demoMode: demoMode,
  ),
);

void main() {
  testWidgets('デモモードのスイッチで、近くの人の検出をデモと本物で切り替える', (tester) async {
    final demoMode = ValueNotifier(true);
    await tester.pumpWidget(_settings(demoMode: demoMode));
    expect(find.text('デモモード'), findsOneWidget);
    expect(find.text('近くの人の代わりに AI 生成の人物を表示'), findsOneWidget);

    await tester.ensureVisible(find.text('デモモード'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('デモモード'));
    await tester.pump();
    expect(demoMode.value, isFalse);
    expect(
      tester
          .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'デモモード'))
          .value,
      isFalse,
    );
  });

  testWidgets('切り替えを渡さない所 (Web デモ) では、デモモードのスイッチを出さない', (tester) async {
    await tester.pumpWidget(_settings());
    expect(find.text('デモモード'), findsNothing);
  });
}
