import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/auth/login_screen.dart';

void main() {
  testWidgets('ログイン失敗後に再試行できる', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          onGoogleSignIn: () async {
            calls++;
            throw Exception('failed');
          },
        ),
      ),
    );
    final button = find.byType(FilledButton);
    final initialPosition = tester.getTopLeft(button);
    await tester.tap(find.text('Google で続ける'));
    await tester.pumpAndSettle();
    expect(find.text('ログインできませんでした。もう一度お試しください。'), findsOneWidget);
    expect(tester.getTopLeft(button), initialPosition);
    await tester.tap(find.text('Google で続ける'));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets('審査用アカウントのメールとパスワードでログインできる', (tester) async {
    String? got;
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          onGoogleSignIn: () async {},
          onTestSignIn: (email, password) async => got = '$email $password',
        ),
      ),
    );
    await tester.ensureVisible(find.text('審査用アカウントでログイン'));
    await tester.tap(find.text('審査用アカウントでログイン'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'メールアドレス'),
      'test1@wearby.test',
    );
    await tester.enterText(find.widgetWithText(TextField, 'パスワード'), 'pw');
    await tester.tap(find.text('ログイン'));
    await tester.pumpAndSettle();
    expect(got, 'test1@wearby.test pw');
  });

  testWidgets('審査用アカウントの入口は、渡された時だけ出す', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: LoginScreen(onGoogleSignIn: () async {})),
    );
    expect(find.text('審査用アカウントでログイン'), findsNothing);
  });

  testWidgets('審査用ログインの失敗後も入力を保ち、パスワードを確認できる', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          onGoogleSignIn: () async {},
          onTestSignIn: (_, _) async => throw Exception('failed'),
        ),
      ),
    );
    await tester.ensureVisible(find.text('審査用アカウントでログイン'));
    await tester.tap(find.text('審査用アカウントでログイン'));
    await tester.pumpAndSettle();
    final email = find.widgetWithText(TextField, 'メールアドレス');
    final password = find.widgetWithText(TextField, 'パスワード');
    await tester.enterText(email, 'test1@wearby.test');
    await tester.enterText(password, 'example-password');
    expect(tester.widget<TextField>(password).obscureText, isTrue);
    await tester.tap(find.byTooltip('パスワードを表示'));
    await tester.pump();
    expect(tester.widget<TextField>(password).obscureText, isFalse);
    await tester.tap(find.text('ログイン'));
    await tester.pumpAndSettle();
    expect(find.text('ログインできませんでした。入力内容と通信を確認してください'), findsOneWidget);
    expect(
      tester.widget<TextField>(email).controller!.text,
      'test1@wearby.test',
    );
    expect(
      tester.widget<TextField>(password).controller!.text,
      'example-password',
    );
  });
}
