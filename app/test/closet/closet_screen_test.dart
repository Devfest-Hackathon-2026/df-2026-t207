import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lib/closet/closet_screen.dart';

const _items = [
  ClosetItem(id: 'w_01', slot: 'bottom', label: 'ワイドパンツ', color: 'チャコール'),
  ClosetItem(id: 'w_03', slot: 'shoes', label: '白スニーカー'),
  ClosetItem(id: 'w_04', slot: 'top', label: 'クルーネックニット', materialGuess: 'ウール'),
  ClosetItem(id: 'w_06', slot: 'outer', label: 'ステンカラーコート', memo: '古着'),
];

Widget _closet({
  List<ClosetItem> items = _items,
  VoidCallback? onAdd,
  Future<void> Function(ClosetItem)? onDelete,
}) {
  return MaterialApp(
    home: ClosetScreen(
      items: items,
      onBack: () {},
      onAddPressed: onAdd ?? () {},
      onDelete: onDelete,
    ),
  );
}

/// スマホの縦長の画面で測る (既定の 800x600 だと 2 段目が画面の外になる)
void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('件数を出し、外側から足元の順に並べる', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_closet());
    expect(find.text('アイテム 4点'), findsOneWidget);
    final coat = tester.getTopLeft(find.text('ステンカラーコート'));
    final knit = tester.getTopLeft(find.text('クルーネックニット'));
    expect(coat.dx < knit.dx, isTrue);
  });

  testWidgets('区分で絞れる', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_closet());
    await tester.tap(find.text('ボトムス'));
    await tester.pump();
    expect(find.text('ワイドパンツ'), findsOneWidget);
    expect(find.text('白スニーカー'), findsNothing);

    await tester.tap(find.text('すべて'));
    await tester.pump();
    expect(find.text('白スニーカー'), findsOneWidget);
  });

  testWidgets('タップで詳しく見られ、素材は推定と出す', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_closet());
    await tester.tap(find.text('クルーネックニット'));
    await tester.pumpAndSettle();
    expect(find.text('素材 (推定)'), findsOneWidget);
    expect(find.text('ウール'), findsOneWidget);
  });

  testWidgets('確かめてからクローゼットから外す', (tester) async {
    _phone(tester);
    final deleted = <String>[];
    await tester.pumpWidget(_closet(onDelete: (i) async => deleted.add(i.id)));
    await tester.tap(find.text('白スニーカー'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('クローゼットから外す'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('やめる'));
    await tester.pumpAndSettle();
    expect(deleted, isEmpty);

    await tester.tap(find.text('クローゼットから外す'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('外す'));
    await tester.pumpAndSettle();
    expect(deleted, ['w_03']);
    expect(find.text('クローゼットから外す'), findsNothing); // 詳しい表示は閉じる
  });

  testWidgets('空の時は撮るボタンを出す', (tester) async {
    _phone(tester);
    var added = 0;
    await tester.pumpWidget(_closet(items: const [], onAdd: () => added++));
    expect(find.text('クローゼットにアイテムはありません'), findsOneWidget);
    await tester.tap(find.text('今日のコーデを撮る'));
    expect(added, 1);
  });
}
