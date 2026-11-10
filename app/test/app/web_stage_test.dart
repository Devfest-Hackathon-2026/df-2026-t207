import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/api/api_models.dart';
import 'package:app/app/web_stage.dart';

NearbyCard _card(String id) => NearbyCard.fromJson({
  'cardId': id,
  'image': '/v1/cards/$id/image',
  'seenAgoSec': 0,
  'expiresAt': '2099-01-01T00:00:00+09:00',
  'items': [],
});

Widget _app({required bool enabled}) => MaterialApp(
  home: Builder(
    builder: (context) =>
        WebStage(enabled: enabled, child: const Text('アプリ本体')),
  ),
);

void main() {
  setUp(() => stage.value = const StageState());

  testWidgets('広い画面では、アプリをあなたのスマホに入れ、すれ違った人と Android アプリを並べる', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(enabled: true));
    expect(find.text('アプリ本体'), findsOneWidget);
    expect(find.text('あなた'), findsOneWidget);
    expect(find.text('すれ違った人'), findsOneWidget);
    expect(find.text('Android アプリ'), findsOneWidget);
    expect(find.text('まだすれ違っていません'), findsOneWidget);
  });

  testWidgets('外枠を出さない時は、アプリだけを出す', (tester) async {
    await tester.pumpWidget(_app(enabled: false));
    expect(find.text('アプリ本体'), findsOneWidget);
    expect(find.text('すれ違った人'), findsNothing);
  });

  test('いいねは、今すれ違った人に出ているカードの時だけ届く', () {
    stageShow(_card('c_1'), null);
    stageLike('c_other', true);
    expect(stage.value.liked, isFalse);
    stageLike('c_1', true);
    expect(stage.value.liked, isTrue);
    stageShow(_card('c_2'), null);
    expect(stage.value.liked, isFalse);
  });
}
