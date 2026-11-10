import 'dart:convert';

import 'package:app/api/api_client.dart';
import 'package:app/api/api_models.dart';
import 'package:app/social/friend_item_match.dart';
import 'package:app/social/friend_outfit_items.dart';
import 'package:app/social/friend_profile_screen.dart';
import 'package:app/social/social_activity.dart';
import 'package:app/viewer/outfit_match_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/friend_preview_images.dart';

const _item = FriendOutfitItem(
  index: 3,
  slot: 'outer',
  label: 'ジャケット',
  color: '紺',
);
const _friend = SocialFriend(id: 'f_123', name: 'はる', postDate: '2026-11-10');

class _MatchApi extends ApiClient {
  _MatchApi() : super(idToken: () async => null);

  String? requested;
  String? matched;

  @override
  Future<NearbyCard> friendItemCard({
    required String friendId,
    required int index,
    required String date,
    required String slot,
    required String label,
    required String color,
  }) async {
    requested = '$friendId/$index/$date/$slot/$label/$color';
    return NearbyCard(
      cardId: 'c_friend',
      image: '/outfit',
      seenAgoSec: 0,
      expiresAt: DateTime(2026, 11, 10),
      items: const [
        CardItem(
          cardItemId: 'a',
          slot: 'outer',
          label: 'ジャケット',
          color: '紺',
          image: '/item',
        ),
      ],
    );
  }

  @override
  Future<MatchResult> match(String cardId, String cardItemId) async {
    matched = '$cardId/$cardItemId';
    return const MatchResult([], null, null);
  }

  @override
  Future<List<WardrobeItem>> getWardrobe({String? slot}) async => [];

  @override
  ImageProvider image(String path, {Object? version}) => previewJacket;
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
  test('フレンドの服を日付と表示内容を添えてカードにする', () async {
    http.Request? request;
    final api = ApiClient(
      idToken: () async => 'token',
      baseUrl: 'https://example.test',
      httpClient: MockClient((r) async {
        request = r;
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'cardId': 'c_1',
              'image': '/image',
              'seenAgoSec': 0,
              'expiresAt': '2026-11-10T23:59:00+09:00',
              'items': [
                {
                  'cardItemId': 'a',
                  'slot': 'outer',
                  'label': 'ジャケット',
                  'color': '紺',
                  'image': '/item',
                },
              ],
            }),
          ),
          200,
        );
      }),
    );
    final card = await api.friendItemCard(
      friendId: 'f_123',
      index: 3,
      date: '2026-11-10',
      slot: 'outer',
      label: 'ジャケット',
      color: '紺',
    );
    expect(request!.url.path, '/v1/friends/f_123/today/items/3/card');
    expect(jsonDecode(request!.body), {
      'date': '2026-11-10',
      'slot': 'outer',
      'label': 'ジャケット',
      'color': '紺',
    });
    expect(card.items.single.cardItemId, 'a');
  });

  testWidgets('フレンドの選んだ服で近くのコーデと同じ照合画面を開く', (tester) async {
    final api = _MatchApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  openFriendItemMatch(context, api, _friend, _item),
              child: const Text('開く'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();
    expect(api.requested, 'f_123/3/2026-11-10/outer/ジャケット/紺');
    expect(api.matched, 'c_friend/a');
    expect(find.byType(OutfitMatchScreen), findsOneWidget);
    expect(find.text('手持ちと照合'), findsOneWidget);
    expect(find.text('ジャケット'), findsOneWidget);
  });

  testWidgets('フレンドのプロフィールの服から照合できる', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _MatchApi();
    final activity = SocialActivity(api: api)..updateAccount(anonymous: false);
    addTearDown(activity.dispose);
    final friend = SocialFriend(
      id: _friend.id,
      name: _friend.name,
      postDate: _friend.postDate,
      todayOutfit: previewOutfit,
      todayItems: const [_item],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: FriendProfileScreen(friend: friend, activity: activity),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('アウター').hitTestable(),
      250,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('アウター'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('手持ちと照合'));
    await tester.pumpAndSettle();
    expect(api.matched, 'c_friend/a');
    expect(find.byType(OutfitMatchScreen), findsOneWidget);
  });
}
