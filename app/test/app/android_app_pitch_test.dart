import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/app/android_app_pitch.dart';

void main() {
  testWidgets('アプリへの誘導は、全機能がアプリにあることとアプリでできることを出す', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AndroidAppPitch())),
    );
    expect(find.text('すべての機能は Android アプリで'), findsOneWidget);
    expect(find.text('Bluetooth ですれ違う'), findsOneWidget);
    expect(find.text('APK をダウンロード'), findsNothing);
  });

  testWidgets('Web デモの「+」の画面では、APK を落とすボタンも出す', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showAndroidAppSheet(context),
              child: const Text('+'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('+'));
    await tester.pumpAndSettle();
    expect(find.text('コーデの投稿はアプリで'), findsOneWidget);
    expect(find.text('APK をダウンロード'), findsOneWidget);
  });
}
