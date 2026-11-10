import 'package:app/api/api_client.dart';
import 'package:app/app/app_banner.dart';
import 'package:app/app/app_palette.dart';
import 'package:app/mypage/my_page_screen.dart';
import 'package:app/shell/app_shell.dart';
import 'package:app/shell/floating_nav_bar.dart';
import 'package:app/social/friend_outfit_items.dart';
import 'package:app/social/friend_profile_screen.dart';
import 'package:app/social/friends_screen.dart';
import 'package:app/social/social_activity.dart';
import 'package:app/viewer/nearby_outfits_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../support/friend_preview_images.dart';

class _TestFriendActivity extends SocialActivity {
  final _people = [
    SocialFriend(
      id: 'haruto',
      name: 'はると',
      postCount: 24,
      streakDays: 3,
      todayOutfit: previewOutfit,
      todayItems: [
        FriendOutfitItem(
          slot: 'top',
          label: 'スウェット',
          color: '生成り',
          image: previewSweatshirt,
        ),
      ],
    ),
    const SocialFriend(id: 'rio', name: 'りお', postCount: 17, streakDays: 0),
    const SocialFriend(id: 'minato', name: 'みなと', postCount: 6, streakDays: 0),
  ];

  @override
  List<SocialFriend> get friends => List.unmodifiable(_people);

  @override
  Future<void> removeFriend(SocialFriend friend) async {
    if (_people.remove(friend)) notifyListeners();
  }
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
  testWidgets('自分のフレンドコードをQRと一緒に表示する', (tester) async {
    const code = 'ABCD1234';
    final activity = SocialActivity(api: ApiClient(idToken: () async => null))
      ..updateAccount(anonymous: false, code: code);
    addTearDown(activity.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FriendsScreen(activity: activity)),
      ),
    );

    await tester.tap(find.byTooltip('自分のコード'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('自分のフレンドコード'), findsOneWidget);
    expect(find.text(code), findsOneWidget);
    final qr = find.byType(QrImageView);
    expect(tester.getSize(qr), const Size.square(208));
    expect(find.text('コピー'), findsNothing);
    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);

    await tester.tap(find.byTooltip('フレンドを追加'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.tap(find.text('コードで申請'));
    await tester.pumpAndSettle();
    final sheet = find.byType(BottomSheet);
    expect(find.text('フレンドコードを入力'), findsOneWidget);
    expect(
      find.descendant(of: sheet, matching: find.byType(TextField)),
      findsOneWidget,
    );
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
  });

  testWidgets('フレンド申請の完了を上部に表示し、取り消すを赤くする', (tester) async {
    const friendRequest =
        '{"requestId":"request-1","displayName":"りお","status":"pending"}';
    final activity = SocialActivity(
      api: ApiClient(
        idToken: () async => 'test-token',
        httpClient: MockClient((request) async {
          final body = switch ((request.method, request.url.path)) {
            ('GET', '/v1/friends') => '{"friends":[]}',
            ('GET', '/v1/friends/requests') =>
              '{"incoming":[],"outgoing":[$friendRequest]}',
            ('POST', '/v1/friends/requests') => friendRequest,
            _ => throw StateError('unexpected request: ${request.url}'),
          };
          return http.Response(
            body,
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    )..updateAccount(anonymous: false, code: 'ABCD1234');
    addTearDown(activity.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FriendsScreen(activity: activity)),
      ),
    );

    await tester.tap(find.byTooltip('フレンドを追加'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('コードで申請'));
    await tester.pumpAndSettle();
    final field = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, 'XYZW1234');
    await tester.tap(find.text('申請する'));
    await tester.pumpAndSettle();
    final banner = find.byType(AppBanner);
    expect(
      find.descendant(of: banner, matching: find.text('申請を送りました')),
      findsOneWidget,
    );
    expect(tester.getTopLeft(banner).dy, lessThan(48));
    final cancel = find.widgetWithText(TextButton, '取り消す');
    expect(
      tester.widget<TextButton>(cancel).style!.foregroundColor!.resolve({}),
      tester.element(cancel).palette.danger,
    );
    await tester.tap(find.byTooltip('通知を閉じる'));
    await tester.pumpAndSettle();
    expect(banner, findsNothing);
  });

  testWidgets('名前で絞り込み、確認後にだけフレンドを削除する', (tester) async {
    final activity = _TestFriendActivity();
    addTearDown(activity.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FriendsScreen(activity: activity)),
      ),
    );

    final search = find.byType(TextField);
    await tester.enterText(search, 'り');
    await tester.pumpAndSettle();
    expect(find.text('はると'), findsNothing);
    expect(find.text('りお'), findsOneWidget);

    await tester.tap(find.byTooltip('りおを削除'));
    await tester.pumpAndSettle();
    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget);
    expect(find.text('りおをフレンドから削除しますか？'), findsOneWidget);
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(find.text('りお'), findsOneWidget);

    await tester.tap(find.byTooltip('りおを削除'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: sheet, matching: find.text('削除')));
    await tester.pumpAndSettle();
    expect(find.text('該当するフレンドはいません'), findsOneWidget);
    expect(find.text('2人'), findsOneWidget);
  });

  testWidgets('名前とアイコンから相手のプロフィールを開き、今日の投稿を表示する', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final activity = _TestFriendActivity();
    addTearDown(activity.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          initialTab: AppTab.community,
          homeBuilder: (_, _) => const Center(child: Text('ホームの内容')),
          myPageBuilder: (_, _) => const SizedBox.shrink(),
          communityBuilder: (_, _) => FriendsScreen(activity: activity),
        ),
      ),
    );

    final nav = find.byType(FloatingNavBar);
    final navElement = tester.element(nav);
    final navPosition = tester.getRect(nav);
    await tester.tap(find.text('はると'));
    await tester.pumpAndSettle();
    final profile = find.byType(FriendProfileScreen);
    expect(profile, findsOneWidget);
    expect(tester.element(nav), same(navElement));
    expect(find.text('マイページ'), findsNothing);
    expect(find.byTooltip('戻る'), findsNothing);
    expect(find.byTooltip('フレンド'), findsOneWidget);
    expect(find.text('投稿数'), findsOneWidget);
    expect(find.text('24件'), findsOneWidget);
    expect(find.text('連続記録'), findsOneWidget);
    expect(find.text('3日'), findsOneWidget);
    expect(find.text('今日の投稿'), findsOneWidget);
    expect(find.bySemanticsLabel('はるとの今日のコーデ'), findsOneWidget);
    expect(find.text('クローゼット'), findsNothing);
    expect(find.text('コーデカレンダー'), findsNothing);
    expect(find.text('保存したアイテム'), findsNothing);

    final header = find.byType(MyPageHeader);
    final name = find.descendant(of: header, matching: find.text('はると'));
    final expanded = tester.getRect(header);
    final expandedNameRatio =
        (tester.getCenter(name).dy - expanded.top) / expanded.height;
    final profileScroll = find
        .descendant(of: profile, matching: find.byType(Scrollable))
        .first;
    tester.state<ScrollableState>(profileScroll).position.jumpTo(180);
    await tester.pumpAndSettle();
    final compact = tester.getRect(header);
    final compactNameRatio =
        (tester.getCenter(name).dy - compact.top) / compact.height;
    expect(compact.top, expanded.top);
    expect(compact.height, lessThan(expanded.height));
    expect(compactNameRatio, greaterThan(expandedNameRatio));
    expect(find.text('24件'), findsOneWidget);
    expect(find.text('3日'), findsOneWidget);
    expect(tester.getRect(nav), navPosition);

    final top = find.text('トップス');
    await tester.scrollUntilVisible(
      top.hitTestable(),
      250,
      scrollable: profileScroll,
    );
    await tester.tap(top);
    await tester.pumpAndSettle();
    expect(find.text('スウェット'), findsOneWidget);
    expect(find.text('生成り'), findsOneWidget);
    expect(nav, findsNothing);
    expect(find.byType(NearbyOutfitsScreen), findsOneWidget);
    expect(find.text('アイテムを追加'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byTooltip('戻る'));
    await tester.pumpAndSettle();

    final profileRoute = ModalRoute.of(tester.element(profile))!;
    await tester.tap(find.byTooltip('フレンド'));
    await tester.pump();
    expect(profileRoute.animation!.status, AnimationStatus.reverse);
    expect(tester.getRect(nav), navPosition);
    await tester.pumpAndSettle();
    expect(profile, findsNothing);
    expect(tester.element(nav), same(navElement));
    final rioRow = find.ancestor(
      of: find.text('りお'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(of: rioRow, matching: find.byType(CircleAvatar)),
    );
    await tester.pumpAndSettle();
    expect(profile, findsOneWidget);
    expect(find.text('17件'), findsOneWidget);
    expect(find.text('0日'), findsOneWidget);
    expect(find.text('今日の公開コーデはありません'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    await tester.tap(find.byTooltip('ホーム'));
    await tester.pump();
    expect(find.text('ホームの内容'), findsOneWidget);
    expect(tester.element(nav), same(navElement));
    await tester.tap(find.byTooltip('フレンド'));
    await tester.pump();
    expect(profile, findsNothing);
    expect(find.text('フレンド一覧'), findsOneWidget);
    expect(tester.element(nav), same(navElement));

    await tester.tap(find.text('りお'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(profile, findsOneWidget);
    await tester.tap(find.byTooltip('ホーム'));
    await tester.pump();
    await tester.tap(find.byTooltip('フレンド'));
    await tester.pump();
    expect(profile, findsNothing);
    expect(find.text('フレンド一覧'), findsOneWidget);
    await tester.pumpAndSettle();
  });
}
