import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lib/auth/name_setup_screen.dart';

void main() {
  testWidgets('初期名を指定した場合は入力済みで次へ進める', (tester) async {
    String? savedName;
    await tester.pumpWidget(
      MaterialApp(
        home: NameSetupScreen(
          initialName: 'あおやま',
          onContinue: (name) async {
            savedName = name;
          },
        ),
      ),
    );
    final next = find.byType(FilledButton);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'あおやま',
    );
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(savedName, 'あおやま');
  });

  testWidgets('名前を入力してから次へ進める', (tester) async {
    String? savedName;
    await tester.pumpWidget(
      MaterialApp(
        home: NameSetupScreen(
          onContinue: (name) async {
            savedName = name;
          },
        ),
      ),
    );
    final next = find.byType(FilledButton);
    expect(tester.widget<FilledButton>(next).onPressed, isNull);
    await tester.enterText(find.byType(TextField), '  あおやま  ');
    await tester.pump();
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(savedName, 'あおやま');
  });
}
