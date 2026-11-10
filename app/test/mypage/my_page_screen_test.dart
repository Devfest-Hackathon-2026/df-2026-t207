import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lib/mypage/my_page_screen.dart';

Widget _page({
  bool isPublishing = false,
  Future<void> Function(bool)? onPublishChanged,
}) {
  return MaterialApp(
    home: MyPageScreen(
      displayName: 'りお',
      isPublishing: isPublishing,
      closetCount: 24,
      onPublishChanged: onPublishChanged ?? (_) async {},
      onClosetPressed: () {},
      onEditName: () {},
      onSettingsPressed: () {},
    ),
  );
}

void main() {
  testWidgets('非公開から公開に切り替える', (tester) async {
    final calls = <bool>[];
    await tester.pumpWidget(_page(onPublishChanged: (v) async => calls.add(v)));

    expect(find.text('非公開'), findsOneWidget);
    await tester.tap(find.text('公開設定'));
    await tester.pumpAndSettle();
    expect(find.text('今日のコーデを公開しますか？'), findsOneWidget);
    await tester.tap(find.text('近くのユーザーに公開'));
    await tester.pumpAndSettle();
    expect(calls, [true]);
  });

  testWidgets('公開中の確認をキャンセルでき、確定すると非公開に切り替える', (tester) async {
    final calls = <bool>[];
    await tester.pumpWidget(
      _page(isPublishing: true, onPublishChanged: (v) async => calls.add(v)),
    );
    await tester.tap(find.text('公開設定'));
    await tester.pumpAndSettle();
    expect(find.text('今日のコーデを非公開にしますか？'), findsOneWidget);
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);

    await tester.tap(find.text('公開設定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('非公開にする'));
    await tester.pumpAndSettle();
    expect(calls, [false]);
  });

  testWidgets('切り替えに失敗したら知らせ、もう一度押せる', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _page(
        onPublishChanged: (_) async {
          calls++;
          throw Exception('failed');
        },
      ),
    );

    await tester.tap(find.text('公開設定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('近くのユーザーに公開'));
    await tester.pumpAndSettle();
    expect(find.text('切り替えられませんでした。もう一度お試しください。'), findsOneWidget);
    await tester.tap(find.text('公開設定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('近くのユーザーに公開'));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets('許可項目はマイページに表示しない', (tester) async {
    await tester.pumpWidget(_page());
    expect(find.byKey(const ValueKey('request-Bluetooth')), findsNothing);
    expect(find.text('許可'), findsNothing);
    expect(find.text('公開設定'), findsOneWidget);
  });

  testWidgets('件数が未取得なら未取得として表示する', (tester) async {
    await tester.pumpWidget(_page());
    expect(find.text('投稿数'), findsOneWidget);
    expect(find.text('連続記録'), findsOneWidget);
    expect(find.text('フレンド —'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(2));
  });

  testWidgets('名前と手持ちの件数を出す', (tester) async {
    await tester.pumpWidget(_page());
    expect(find.text('りお'), findsOneWidget);
    expect(find.text('24 点'), findsOneWidget);
  });
  testWidgets('カレンダーで月を切り替えられる', (tester) async {
    final now = DateTime.now();
    final previous = DateTime(now.year, now.month - 1);
    await tester.pumpWidget(_page());
    expect(find.text('${now.year}年${now.month}月'), findsOneWidget);
    await tester.tap(find.byTooltip('前の月'));
    await tester.pumpAndSettle();
    expect(find.text('${previous.year}年${previous.month}月'), findsOneWidget);
  });

  testWidgets('月を変えると、その月の 1 日を知らせる (記録は月ごとに読む)', (tester) async {
    final months = <DateTime>[];
    await tester.pumpWidget(
      MaterialApp(
        home: MyPageScreen(
          displayName: 'りお',
          isPublishing: false,
          onPublishChanged: (_) async {},
          onClosetPressed: () {},
          onEditName: () {},
          onSettingsPressed: () {},
          onCalendarMonthChanged: months.add,
        ),
      ),
    );
    final now = DateTime.now();
    await tester.tap(find.byTooltip('前の月'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('次の月'));
    await tester.tap(find.byTooltip('次の月'));
    await tester.pumpAndSettle();
    expect(months, [
      DateTime(now.year, now.month - 1),
      DateTime(now.year, now.month),
      DateTime(now.year, now.month + 1),
    ]);
  });
}
