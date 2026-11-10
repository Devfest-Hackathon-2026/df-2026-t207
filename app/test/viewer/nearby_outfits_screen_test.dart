import 'package:app/api/api_models.dart';
import 'package:app/app/app_loading.dart';
import 'package:app/shell/app_shell.dart';
import 'package:app/viewer/nearby_outfits_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('保存、通報とブロックを下から開き、選んだ操作だけ送る', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final card = NearbyCard(
      cardId: 'test-card',
      image: '/image',
      seenAgoSec: 0,
      expiresAt: DateTime.now().add(const Duration(minutes: 30)),
      items: const [
        CardItem(
          cardItemId: 'shirt',
          slot: 'top',
          label: 'シャツ',
          color: '白',
          image: '/shirt',
        ),
        CardItem(
          cardItemId: 'denim',
          slot: 'bottom',
          label: 'デニム',
          color: '青',
          image: '/denim',
        ),
      ],
    );
    final reports = <(String, String)>[];
    final blocked = <String>[];
    final saved = <(String, String)>[];
    final deleted = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: NearbyOutfitsScreen(
          loadNearby: () async =>
              NearbyResult(cards: [card], viewerPublishing: true),
          imageFor: (_) => null,
          onReport: (id, reason) async => reports.add((id, reason)),
          onBlock: (id) async => blocked.add(id),
          onSaveItem: (id, itemId) async {
            saved.add((id, itemId));
            return 'save-$itemId';
          },
          onDeleteSave: (id) async => deleted.add(id),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('保存'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.tap(find.byTooltip('シャツを保存'));
    await tester.pumpAndSettle();
    expect(saved, [('test-card', 'shirt')]);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byTooltip('シャツの保存を解除'), findsOneWidget);
    await tester.tap(find.byTooltip('デニムを保存'));
    await tester.pumpAndSettle();
    expect(saved, [('test-card', 'shirt'), ('test-card', 'denim')]);
    await tester.tap(find.byTooltip('シャツの保存を解除'));
    await tester.pumpAndSettle();
    expect(deleted, ['save-shirt']);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byTooltip('シャツを保存'), findsOneWidget);
    expect(find.byTooltip('デニムの保存を解除'), findsOneWidget);
    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);

    Future<void> openAction(String label) async {
      await tester.tap(find.byTooltip('ブロック・通報'));
      await tester.pumpAndSettle();
      final buttons = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(TextButton),
      );
      expect(
        tester
            .widgetList<TextButton>(buttons)
            .map((button) => (button.child as Text).data),
        ['ブロック', 'キャンセル', '通報'],
      );
      expect(find.text('コーデのメニュー'), findsNothing);
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
    }

    await openAction('通報');
    expect(find.text('通報理由'), findsOneWidget);
    await tester.tap(find.text('嫌がらせ'));
    await tester.pumpAndSettle();
    expect(reports, [('test-card', 'harassment')]);
    await tester.tap(find.byTooltip('通知を閉じる'));
    await tester.pumpAndSettle();

    await openAction('ブロック');
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(blocked, isEmpty);
    await openAction('ブロック');
    await tester.tap(find.text('ブロック'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(blocked, ['test-card']);
    expect(find.text('近くのコーデはまだありません'), findsOneWidget);
  });

  testWidgets('非公開のコーデは公開を案内し、周囲にコーデがないときは再確認できる', (tester) async {
    var publishing = false;
    var loads = 0;
    var captures = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: NearbyOutfitsScreen(
          loadNearby: () async {
            loads++;
            return NearbyResult(cards: const [], viewerPublishing: publishing);
          },
          imageFor: (_) => null,
          outfitToPublish: const AssetImage(
            'assets/images/first_outfit_illustration.png',
          ),
          onCapturePressed: () => captures++,
          onPublishPressed: () async => publishing = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('コーデを公開して、\nみんなのを見よう。'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('公開する'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('近くのユーザーに公開します。公開は今日の24時に終了します。'), findsOneWidget);
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(publishing, isFalse);
    await tester.tap(find.bySemanticsLabel('公開する'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('公開する'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(publishing, isTrue);
    expect(captures, 0);
    expect(find.text('近くのコーデはまだありません'), findsOneWidget);
    final ripples = find.byType(RipplingHanger);
    final scaffold = find.byType(Scaffold);
    expect(tester.getSize(ripples), tester.getSize(scaffold));
    expect(tester.widget<Scaffold>(scaffold).backgroundColor, Colors.white);
    expect(find.byType(AppLoadingIndicator), findsNothing);
    final retry = find.widgetWithText(FilledButton, '再確認');
    expect(
      tester.getRect(scaffold).bottom - tester.getRect(retry).bottom,
      lessThanOrEqualTo(40),
    );
    await tester.tap(find.text('再確認'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(loads, 3);
  });

  testWidgets('探すを押してから取得し、横と下のスワイプでコーデと詳細を切り替える', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var loadCount = 0;
    (String, String)? matchSelection;
    final expiresAt = DateTime.now().add(const Duration(minutes: 30));
    final cards = [
      NearbyCard(
        cardId: '1',
        image: '/one',
        seenAgoSec: 180,
        expiresAt: expiresAt,
        isDemo: true,
        items: const [],
      ),
      NearbyCard(
        cardId: '2',
        image: '/two',
        seenAgoSec: 360,
        expiresAt: expiresAt,
        items: const [
          CardItem(
            cardItemId: 'jacket',
            slot: 'outer',
            label: 'デニムジャケット',
            color: 'インディゴ',
            image: '/jacket',
          ),
          CardItem(
            cardItemId: 'shirt',
            slot: 'top',
            label: 'シャツ',
            color: '白',
            image: '/shirt',
          ),
          CardItem(
            cardItemId: 'pants',
            slot: 'bottom',
            label: 'パンツ',
            color: '黒',
            image: '/pants',
          ),
          CardItem(
            cardItemId: 'shoes',
            slot: 'shoes',
            label: 'スニーカー',
            color: '白',
            image: '/shoes',
          ),
        ],
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          homeBuilder: (_, _) => const Text('ホーム画面'),
          myPageBuilder: (_, _) => const Text('マイページ画面'),
          onSearchPressed: (context) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => NearbyOutfitsScreen(
                loadNearby: () async {
                  loadCount++;
                  return NearbyResult(cards: cards, viewerPublishing: true);
                },
                imageFor: (_) => null,
                onMatch: (card, item) =>
                    matchSelection = (card.cardId, item.cardItemId),
                isSimulated: true,
                showPreviewLabels: false,
              ),
            ),
          ),
        ),
      ),
    );

    expect(loadCount, 0);
    await tester.tap(find.byTooltip('探す'));
    await tester.pumpAndSettle();
    expect(loadCount, 1);
    expect(find.text('3分前'), findsOneWidget);
    expect(find.text('いいね'), findsOneWidget);
    expect(find.byTooltip('保存'), findsOneWidget);
    expect(find.text('デモ'), findsNothing);
    expect(find.text('AI 生成'), findsNothing);

    await tester.drag(find.byType(PageView), const Offset(-330, 0));
    await tester.pumpAndSettle();
    expect(find.text('6分前'), findsOneWidget);
    final like = find.widgetWithText(FilledButton, 'いいね');
    final save = find.byTooltip('保存');
    final likePosition = tester.getRect(like);
    final savePosition = tester.getRect(save);
    final likeContent = tester
        .getRect(find.byIcon(Icons.favorite_border))
        .expandToInclude(tester.getRect(find.text('いいね')));
    expect((likeContent.center - likePosition.center).distance, lessThan(0.5));
    expect(
      tester.getCenter(find.byIcon(Icons.bookmark_border)),
      savePosition.center,
    );

    await tester.drag(find.byType(PageView), const Offset(0, 140));
    await tester.pumpAndSettle();
    expect(find.text('着用アイテム'), findsOneWidget);
    expect(tester.getRect(like), likePosition);
    expect(tester.getRect(save), savePosition);
    final searchButton = find.widgetWithText(FilledButton, '手持ちと照合');
    final searchIcon = find.descendant(
      of: searchButton,
      matching: find.byIcon(Icons.search),
    );
    final searchContent = tester
        .getRect(searchIcon)
        .expandToInclude(tester.getRect(find.text('手持ちと照合')));
    expect(
      (searchContent.center - tester.getCenter(searchButton)).distance,
      lessThan(0.5),
    );
    expect(tester.widget<FilledButton>(searchButton).onPressed, isNull);
    await tester.tap(find.text('デニムジャケット'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(searchButton).onPressed, isNotNull);
    await tester.tap(searchButton);
    expect(matchSelection, ('2', 'jacket'));

    final lastItemDot = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics && widget.properties.label == '着用アイテムのスクロール位置 4',
    );
    expect(tester.widget<Semantics>(lastItemDot).properties.selected, isFalse);
    await tester.drag(find.byType(ListView), const Offset(-120, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<Semantics>(lastItemDot).properties.selected, isTrue);

    await tester.tapAt(const Offset(200, 180));
    await tester.pumpAndSettle();
    expect(find.text('6分前'), findsOneWidget);
    expect(tester.getRect(like), likePosition);
    expect(tester.getRect(save), savePosition);

    await tester.drag(find.text('いいね'), const Offset(0, 48));
    await tester.pumpAndSettle();
    expect(find.text('着用アイテム'), findsOneWidget);

    await tester.tap(find.byTooltip('戻る'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('戻る'));
    await tester.pumpAndSettle();
    expect(find.text('ホーム画面'), findsOneWidget);
  });
}
