import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lib/auth/login_screen.dart';
import '../../lib/auth/name_setup_screen.dart';
import '../../lib/auth/first_outfit_screen.dart';

void main() {
  testWidgets('ログインと名前設定の見出しが同じ高さと大きさになる', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(onGoogleSignIn: () async {}),
      ),
    );
    final login = find.text('コーデから、つながろう。');
    final loginCenter = tester.getCenter(login);
    final loginStyle = tester.widget<Text>(login).style;
    final loginActionTop = tester.getTopLeft(find.byType(FilledButton)).dy;

    await tester.pumpWidget(
      MaterialApp(home: NameSetupScreen(onContinue: (_) async {})),
    );
    final name = find.text('アカウント名は？');
    expect(tester.getCenter(name).dy, closeTo(loginCenter.dy, 0.1));
    expect(tester.widget<Text>(name).style, loginStyle);
    expect(
      tester.getTopLeft(find.byType(FilledButton)).dy,
      closeTo(loginActionTop, 0.1),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: FirstOutfitScreen(
          displayName: 'あおやま',
          onRecord: () {},
          onLater: () {},
        ),
      ),
    );
    final welcome = find.text('あおやまさん、こんにちは');
    expect(tester.getCenter(welcome).dy, closeTo(loginCenter.dy, 0.1));
    expect(tester.widget<Text>(welcome).style, loginStyle);
    expect(
      tester.getTopLeft(find.byType(FilledButton)).dy,
      closeTo(loginActionTop, 0.1),
    );
  });
}
