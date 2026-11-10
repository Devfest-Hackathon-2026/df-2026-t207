import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lib/auth/first_outfit_screen.dart';

void main() {
  testWidgets('入力した名前と記録・後にするの操作を表示する', (tester) async {
    var recorded = false;
    var skipped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: FirstOutfitScreen(
          displayName: 'あおやま',
          onRecord: () => recorded = true,
          onLater: () => skipped = true,
        ),
      ),
    );
    expect(find.text('あおやまさん、こんにちは'), findsOneWidget);
    expect(find.text('最初のコーデを投稿しよう'), findsOneWidget);
    await tester.ensureVisible(find.text('コーデを投稿する'));
    await tester.tap(find.text('コーデを投稿する'));
    expect(recorded, isTrue);
    await tester.ensureVisible(find.text('後にする'));
    await tester.tap(find.text('後にする'));
    expect(skipped, isTrue);
  });
  testWidgets('後にするから未登録のホームへ進む', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: FirstOutfitScreen(displayName: 'あおやま')),
    );
    await tester.ensureVisible(find.text('後にする'));
    await tester.tap(find.text('後にする'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Wearby'), findsOneWidget);
    expect(find.text('今日のコーデ'), findsOneWidget);
    expect(find.text('後にする'), findsNothing);
  });
}
