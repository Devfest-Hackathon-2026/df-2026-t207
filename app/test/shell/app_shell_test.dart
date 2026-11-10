import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lib/shell/app_shell.dart';
import '../../lib/shell/floating_nav_bar.dart';

Widget _shell({void Function(BuildContext)? onPost}) {
  return MaterialApp(
    home: AppShell(
      homeBuilder: (context, goTo) => Center(
        child: TextButton(
          onPressed: () => goTo(AppTab.myPage),
          child: const Text('ホームの中身'),
        ),
      ),
      myPageBuilder: (context, goTo) => const Center(child: Text('マイページの中身')),
      onPostPressed: onPost ?? (_) {},
    ),
  );
}

bool _visible(WidgetTester tester, String text) =>
    find.text(text).hitTestable().evaluate().isNotEmpty;

void main() {
  testWidgets('下のメニューで各タブに移れる', (tester) async {
    await tester.pumpWidget(_shell());
    expect(_visible(tester, 'ホームの中身'), isTrue);

    await tester.tap(find.byTooltip('マイページ'));
    await tester.pump();
    expect(_visible(tester, 'マイページの中身'), isTrue);
    expect(_visible(tester, 'ホームの中身'), isFalse);

    await tester.tap(find.byTooltip('探す'));
    await tester.pump();
    expect(_visible(tester, '探す'), isTrue);

    await tester.tap(find.byTooltip('フレンド'));
    await tester.pump();
    expect(_visible(tester, 'フレンド'), isTrue);

    await tester.tap(find.byTooltip('ホーム'));
    await tester.pump();
    expect(_visible(tester, 'ホームの中身'), isTrue);
  });

  testWidgets('投稿はタブを変えずに投稿の処理を呼ぶ', (tester) async {
    var posted = 0;
    await tester.pumpWidget(_shell(onPost: (_) => posted++));
    await tester.tap(find.byTooltip('投稿'));
    await tester.pump();
    expect(posted, 1);
    expect(_visible(tester, 'ホームの中身'), isTrue);
  });

  testWidgets('選択ハイライトは移動中の位置から次のタブへ向かう', (tester) async {
    await tester.pumpWidget(_shell());
    final highlight = find.byType(AnimatedPositionedDirectional);
    final home = tester.getCenter(find.byTooltip('ホーム'));
    final myPage = tester.getCenter(find.byTooltip('マイページ'));
    final search = tester.getCenter(find.byTooltip('探す'));
    expect(tester.getCenter(highlight), home);

    await tester.tap(find.byTooltip('マイページ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final moving = tester.getCenter(highlight);
    expect(moving.dx, inExclusiveRange(home.dx, myPage.dx));

    await tester.tap(find.byTooltip('探す'));
    await tester.pump();
    expect(tester.getCenter(highlight), moving);
    await tester.pumpAndSettle();
    expect(tester.getCenter(highlight), search);
  });

  testWidgets('画面の中から別のタブへ移れる', (tester) async {
    await tester.pumpWidget(_shell());
    await tester.tap(find.text('ホームの中身'));
    await tester.pump();
    expect(_visible(tester, 'マイページの中身'), isTrue);
  });

  testWidgets('ホーム以外で戻るとホームに戻る', (tester) async {
    await tester.pumpWidget(_shell());
    await tester.tap(find.byTooltip('マイページ'));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(_visible(tester, 'ホームの中身'), isTrue);
  });
}
