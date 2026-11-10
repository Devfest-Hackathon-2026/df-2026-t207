import 'package:app/capture/outfit_items_review_screen.dart';
import 'package:app/common/outfit_capture_prompt.dart';
import 'package:app/common/outfit_item_tile.dart';
import 'package:app/home/home_screen.dart';
import 'package:app/social/friend_outfit_items.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/friend_preview_images.dart';

Widget _home({
  required bool hasTodayOutfit,
  List<HomeOutfitItem> items = const [],
  List<HomeFriendPost> friendPosts = const [],
  ImageProvider? todayOutfitImage,
  VoidCallback? onCapture,
  VoidCallback? onItems,
  VoidCallback? onNotifications,
  Future<List<HomeOutfitItem>> Function()? loadClosetItems,
}) {
  return MaterialApp(
    home: HomeScreen(
      allowLocalOutfitEdits: true,
      hasTodayOutfit: hasTodayOutfit,
      isPublishing: true,
      viewCountToday: 3,
      items: items,
      todayOutfitImage: todayOutfitImage,
      friendPosts: friendPosts,
      onCapturePressed: onCapture ?? () {},
      onItemsPressed: onItems,
      loadClosetItems: loadClosetItems,
      onPublishPressed: () {},
      onNotificationsPressed: onNotifications,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('jp.dfhack26.app/viewer_security');
  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null),
  );
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  testWidgets('今日のコーデがある時は見られた回数と着用アイテムを外側から順に出す', (tester) async {
    // スマホの縦長の画面で測る (既定の 800x600 だと着用アイテムが画面の外になる)
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    var itemsTapped = 0;
    await tester.pumpWidget(
      _home(
        hasTodayOutfit: true,
        items: const [
          HomeOutfitItem(slot: 'shoes', label: '白スニーカー'),
          HomeOutfitItem(slot: 'outer', label: 'ステンカラーコート'),
          HomeOutfitItem(slot: 'top', label: 'クルーネックニット'),
        ],
        onItems: () => itemsTapped++,
      ),
    );

    expect(find.text('3'), findsOneWidget);
    expect(find.text('近くに公開中'), findsOneWidget);
    expect(find.bySemanticsLabel('撮影する'), findsNothing);
    expect(find.byType(ListView), findsNothing);

    final outer = tester.getTopLeft(find.text('アウター')).dx;
    final top = tester.getTopLeft(find.text('トップス')).dx;
    final shoes = tester.getTopLeft(find.text('シューズ')).dx;
    expect(outer < top && top < shoes, isTrue);

    await tester.tap(find.text('着用アイテム'));
    expect(itemsTapped, 1);
  });

  for (final (count, lastSlot) in [(4, 'shoes'), (5, 'bag')]) {
    testWidgets('着用アイテムが$count件の時は横にスワイプして最後の服を開ける', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _home(
          hasTodayOutfit: true,
          todayOutfitImage: previewOutfit,
          items: [
            for (final slot in [
              'outer',
              'top',
              'bottom',
              'shoes',
              'bag',
            ].take(count))
              HomeOutfitItem(slot: slot, label: slotLabel(slot)),
          ],
        ),
      );

      final strip = find.byType(ListView);
      final label = slotLabel(lastSlot);
      final lastTile = find.widgetWithText(OutfitItemTile, label);
      final rightEdge = tester.getRect(strip).right;
      final fourthTile = find.widgetWithText(OutfitItemTile, 'シューズ');
      expect(tester.getRect(fourthTile).right, greaterThan(rightEdge));

      await tester.drag(strip, const Offset(-240, 0));
      await tester.pumpAndSettle();
      expect(tester.getRect(lastTile).right, closeTo(rightEdge, 0.01));

      await tester.tap(lastTile);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      final memo = find.text('$labelのメモ');
      final transitions = find.descendant(
        of: find.byType(OutfitItemsReviewScreen),
        matching: find.byType(SlideTransition),
      );
      final panel = find.ancestor(of: memo, matching: transitions);
      final itemPanel = find.ancestor(
        of: find.byType(ListView),
        matching: transitions,
      );
      double opacity(Finder child) => tester
          .element(child)
          .findAncestorWidgetOfExactType<FadeTransition>()!
          .opacity
          .value;
      expect(opacity(itemPanel), 0);
      expect(opacity(panel), 0);
      await tester.pump(const Duration(milliseconds: 195));
      expect(opacity(itemPanel), greaterThan(0));
      expect(opacity(panel), 0);
      await tester.pumpAndSettle();
      expect(memo, findsOneWidget);
      expect(tester.widget<SlideTransition>(panel).position.value, Offset.zero);
      final detailStrip = find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(detailStrip).position;
      expect(position.pixels, greaterThan(0));
      expect(position.pixels, closeTo(position.maxScrollExtent, 0.01));
      await tester.tap(find.byTooltip('戻る'));
      await tester.pumpAndSettle();
      expect(lastTile, findsOneWidget);
    });
  }

  testWidgets('今日のコーデが無い時は撮るボタンを出し、着用アイテムを出さない', (tester) async {
    var captured = 0;
    await tester.pumpWidget(
      _home(hasTodayOutfit: false, onCapture: () => captured++),
    );

    expect(find.text('コーデを投稿して、\nみんなのを見よう。'), findsOneWidget);
    expect(find.text('着用アイテム'), findsNothing);
    await tester.tap(find.bySemanticsLabel('撮影する'));
    expect(captured, 1);
  });

  testWidgets('ホームはフレンドの投稿欄を表示する', (tester) async {
    await tester.pumpWidget(_home(hasTodayOutfit: false));
    expect(find.text('フレンドの投稿'), findsOneWidget);
    expect(find.text('フレンドの投稿はまだありません'), findsOneWidget);
    expect(find.text('近くのコーデを見る'), findsNothing);
  });

  testWidgets('ホームのフレンド投稿から選んだ服の詳細を開ける', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    int? matchedIndex;
    final likes = <bool>[];
    final saved = <int>[];
    final protection = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('jp.dfhack26.app/viewer_security'),
          (call) async {
            protection.add(call.method);
            return null;
          },
        );
    await tester.pumpWidget(
      _home(
        hasTodayOutfit: false,
        friendPosts: [
          HomeFriendPost(
            displayName: 'はると',
            timeLabel: '今日',
            image: previewOutfit,
            items: [
              FriendOutfitItem(index: 4, slot: 'outer', label: 'ワークジャケット'),
              FriendOutfitItem(
                index: 1,
                slot: 'bottom',
                label: 'ワイドデニム',
                color: 'ライトブルー',
              ),
            ],
            onMatch: (_, item) async => matchedIndex = item.index,
            liked: true,
            onLike: (value) async => likes.add(value),
            onToggleSave: (index) async => saved.add(index),
            isSaved: (index) => index == 1,
          ),
        ],
      ),
    );

    final bottom = find.text('ボトムス');
    await tester.scrollUntilVisible(
      bottom.hitTestable(),
      250,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(bottom);
    await tester.pumpAndSettle();
    expect(find.text('ワイドデニム'), findsOneWidget);
    expect(find.text('ライトブルー'), findsOneWidget);
    expect(protection, ['enable']);
    await tester.tap(find.text('いいね'));
    await tester.pumpAndSettle();
    expect(likes, [false]);
    await tester.tap(find.byTooltip('保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('ワイドデニムの保存を解除'));
    await tester.pumpAndSettle();
    expect(saved, [1]);
    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('手持ちと照合'));
    await tester.pumpAndSettle();
    expect(matchedIndex, 1);
    expect(find.text('アイテムを追加'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byTooltip('戻る'));
    await tester.pumpAndSettle();
    expect(protection, ['enable', 'disable']);
  });

  testWidgets('フレンドのメモだけの項目は表示し、照合と保存の対象にしない', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _home(
        hasTodayOutfit: false,
        friendPosts: [
          HomeFriendPost(
            displayName: 'はると',
            timeLabel: '今日',
            image: previewOutfit,
            items: const [
              FriendOutfitItem(index: 0, slot: 'outer', label: 'ジャケット'),
              FriendOutfitItem(slot: '', label: 'その他', memo: '帽子は手編み'),
            ],
            onMatch: (_, _) async {},
            onToggleSave: (_) async {},
          ),
        ],
      ),
    );
    final note = find.text('その他');
    await tester.scrollUntilVisible(
      note.hitTestable(),
      250,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(note);
    await tester.pumpAndSettle();
    expect(find.text('帽子は手編み'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '手持ちと照合'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('保存'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('ジャケットを保存'), findsOneWidget);
    expect(find.byTooltip('その他を保存'), findsNothing);
  });

  testWidgets('未投稿カードは縮むと短いコピーに切り替わり、撮影ボタンが残る', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var captured = 0;
    await tester.pumpWidget(
      _home(
        hasTodayOutfit: false,
        onCapture: () => captured++,
        friendPosts: List.filled(
          3,
          const HomeFriendPost(
            displayName: 'はると',
            timeLabel: '今日',
            image: AssetImage('assets/images/login_illustration.png'),
          ),
        ),
      ),
    );

    final card = find.byType(OutfitCapturePrompt);
    final button = find.bySemanticsLabel('撮影する');
    final notifications = tester.getRect(find.byTooltip('通知'));
    final initialCard = tester.element(card);
    final initialButton = tester.element(button);
    final initialHeight = tester.getSize(card).height;
    final position = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;

    position.jumpTo(370);
    await tester.pumpAndSettle();
    expect(tester.getSize(card).height, lessThan(initialHeight));
    expect(tester.element(card), same(initialCard));
    expect(tester.element(button), same(initialButton));
    expect(find.text('コーデを投稿しよう'), findsOneWidget);
    expect(tester.getRect(find.byTooltip('通知')), notifications);
    await tester.tap(button);
    expect(captured, 1);

    position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(tester.getSize(card).height, initialHeight);
    expect(find.text('コーデを投稿して、\nみんなのを見よう。'), findsOneWidget);
  });

  testWidgets('今日のコーデのカードが固定ヘッダーの下でバナーに縮む', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _home(
        hasTodayOutfit: true,
        friendPosts: [
          for (final name in ['はると', 'りお', 'みなと'])
            HomeFriendPost(
              displayName: name,
              timeLabel: '今日',
              image: const AssetImage('assets/images/login_illustration.png'),
            ),
        ],
      ),
    );
    final header = find.bySemanticsLabel('Wearby');
    final notifications = find.byTooltip('通知');
    expect(find.text('ホーム'), findsNothing);
    expect(tester.getCenter(header).dx, closeTo(195, 0.01));
    final initialHeader = tester.getRect(header);
    final initialNotifications = tester.getRect(notifications);
    final card = find
        .descendant(
          of: find.byType(SliverPersistentHeader),
          matching: find.byType(ClipRRect),
        )
        .first;
    final initialCard = tester.element(card);
    final initialHeight = tester.getSize(card).height;
    final count = tester.element(find.text('3'));
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    position.jumpTo(180);
    await tester.pumpAndSettle();
    final partialHeight = tester.getSize(card).height;
    expect(partialHeight, lessThan(initialHeight));
    expect(tester.element(card), same(initialCard));
    expect(tester.element(find.text('3')), same(count));

    position.jumpTo(345);
    await tester.pumpAndSettle();
    final compactHeight = tester.getSize(card).height;
    expect(compactHeight, lessThan(partialHeight));
    expect(tester.element(card), same(initialCard));
    expect(tester.element(find.text('3')), same(count));
    expect(find.text('今日見られた回数'), findsNothing);
    expect(find.text('フレンドの投稿'), findsOneWidget);
    expect(tester.getRect(header), initialHeader);
    expect(tester.getRect(notifications), initialNotifications);

    position.jumpTo(1000);
    await tester.pumpAndSettle();
    expect(tester.getSize(card).height, compactHeight);
    expect(find.text('りお'), findsOneWidget);
    expect(tester.getRect(notifications), initialNotifications);

    position.jumpTo(180);
    await tester.pumpAndSettle();
    expect(tester.getSize(card).height, partialHeight);

    position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(tester.getSize(card).height, initialHeight);
    expect(find.text('今日のコーデ'), findsOneWidget);
  });

  testWidgets('通知ボタンから通知の操作を呼び出す', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _home(hasTodayOutfit: false, onNotifications: () => tapped = true),
    );
    await tester.tap(find.byTooltip('通知'));
    expect(tapped, isTrue);
  });

  testWidgets('投稿済みのコーデでクローゼットを検索し、メモだけでも追加できる', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _home(
        hasTodayOutfit: true,
        items: const [HomeOutfitItem(slot: 'outer', label: 'ジャケット')],
        loadClosetItems: () async => const [
          HomeOutfitItem(slot: 'bag', label: 'キャンバストート', memo: '生成り'),
          HomeOutfitItem(slot: 'top', label: 'ネイビーニット'),
        ],
      ),
    );
    await tester.tap(find.text('着用アイテム'));
    await tester.pumpAndSettle();
    final posted = find.widgetWithText(FilledButton, '投稿済み');
    final strip = find.byType(ListView);
    final wornRect = tester.getRect(strip);
    expect(tester.widget<FilledButton>(posted).onPressed, isNull);
    expect(find.text('アウターのメモ'), findsOneWidget);

    await tester.tap(find.text('アイテムを追加'));
    await tester.pumpAndSettle();
    final field = find.byType(TextField);
    expect(tester.getRect(strip), wornRect);
    expect(find.text('アウターのメモ'), findsNothing);
    expect(find.byTooltip('アウターを外す'), findsNothing);
    final newItem = find.text('新しく追加');
    expect(
      tester.getCenter(newItem).dx,
      lessThan(tester.getCenter(find.text('キャンバストート')).dx),
    );
    await tester.enterText(field, 'トート');
    await tester.pumpAndSettle();
    expect(find.text('ネイビーニット'), findsNothing);
    expect(newItem, findsOneWidget);
    expect(tester.getRect(strip), wornRect);
    await tester.tap(find.text('キャンバストート'));
    await tester.pumpAndSettle();
    expect(find.text('バッグのメモ'), findsOneWidget);
    expect(tester.widget<TextField>(field).controller!.text, '生成り');

    final expandedWornRect = tester.getRect(strip);
    await tester.tap(find.text('アイテムを追加'));
    await tester.pumpAndSettle();
    expect(tester.getRect(strip), expandedWornRect);
    await tester.tap(newItem);
    await tester.pumpAndSettle();
    expect(tester.getRect(strip), expandedWornRect);
    await tester.enterText(field, 'チェック柄のストール');
    await tester.pump();
    await tester.tap(find.text('メモで追加'));
    await tester.pumpAndSettle();
    expect(find.text('その他のメモ'), findsOneWidget);
    expect(tester.widget<TextField>(field).controller!.text, 'チェック柄のストール');
    expect(tester.widget<FilledButton>(posted).onPressed, isNull);
  });
}
