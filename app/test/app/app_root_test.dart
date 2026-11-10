import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show SemanticsAction;

import 'package:app/api/api_client.dart';
import 'package:app/app/app.dart';
import 'package:app/app/app_banner.dart';
import 'package:app/app/app_loading.dart';
import 'package:app/app/main_shell.dart';
import 'package:app/ble/ble_controller.dart';
import 'package:app/capture/outfit_camera_screen.dart';
import 'package:app/capture/outfit_review_background.dart';
import 'package:app/capture/outfit_submission.dart';
import 'package:app/capture/processed_outfit_screen.dart';
import 'package:app/home/home_screen.dart';
import 'package:app/mypage/profile_photo.dart';
import 'package:app/register/outfit_job.dart';
import 'package:app/shell/floating_nav_bar.dart';
import 'package:app/social/friend_avatar.dart';
import 'package:app/social/friend_profile_screen.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/dev_auth_service.dart';

// 1x1 の透明な PNG
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

class _JobStream implements OutfitJobSource {
  final controller = StreamController<OutfitJob?>.broadcast();

  @override
  Stream<OutfitJob?> watch(String uid, String jobId) => controller.stream;
}

ApiClient _fakeApi({
  String meName = 'りお',
  Map<String, Object?> Function()? nearby,
  ValueChanged<String>? onNameSaved,
  VoidCallback? onUnpublish,
  Future<void> Function()? waitForMe,
  String? outfitDate,
  bool hasTodayOutfit = true,
  bool isPublishing = true,
  FutureOr<http.Response?> Function(http.Request)? respond,
}) => ApiClient(
  idToken: () async => 'tok',
  httpClient: MockClient((r) async {
    final response = await respond?.call(r);
    if (response != null) return response;
    final path = r.url.path;
    if (path == '/v1/outfits/today' && !hasTodayOutfit) {
      return http.Response('{"error":{"code":"not_found"}}', 404);
    }
    if (path.endsWith('/image')) return http.Response.bytes(_png, 200);
    if (path == '/v1/outfits/process') {
      return http.Response('{"status":"succeeded"}', 200);
    }
    if (path == '/v1/me' && r.method == 'GET') await waitForMe?.call();
    if (path == '/v1/me' && r.method == 'PATCH') {
      meName =
          (jsonDecode(r.body) as Map<String, dynamic>)['displayName'] as String;
      onNameSaved?.call(meName);
    }
    if (path == '/v1/publish' && r.method == 'PUT') {
      final visibility =
          (jsonDecode(r.body) as Map<String, dynamic>)['visibility'] as String;
      isPublishing = visibility == 'nearby';
      if (!isPublishing) onUnpublish?.call();
      return http.Response(jsonEncode({'visibility': visibility}), 200);
    }
    if (path == '/v1/demo/nearby' && nearby != null) {
      return http.Response(jsonEncode(nearby()), 200);
    }
    final name = switch (path) {
      '/v1/me' => 'me',
      '/v1/outfits/today' => 'today-outfit',
      '/v1/wardrobe' => 'wardrobe',
      _ => throw StateError('unexpected $path'),
    };
    var body = File('../docs/api-examples/$name.json').readAsStringSync();
    if (name == 'me') {
      final me = jsonDecode(body) as Map<String, dynamic>;
      me['displayName'] = meName;
      me['publishing'] = {
        'visibility': isPublishing ? 'nearby' : 'private',
        if (isPublishing)
          'until': DateTime.now()
              .add(const Duration(hours: 1))
              .toIso8601String(),
      };
      body = jsonEncode(me);
    }
    if (name == 'today-outfit' && outfitDate != null) {
      body = body.replaceFirst('"2026-11-08"', jsonEncode(outfitDate));
    }
    return http.Response.bytes(
      utf8.encode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }),
);

void main() {
  testWidgets('ホームのアイコンと名前からプロフィールを開き、非公開でもプロフィール画像を取得する', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final auth = DevAuthService();
    addTearDown(auth.dispose);
    await auth.signInAnonymously();
    var published = true;
    var privateProfileImageRequests = 0;
    var holdProfileImage = false;
    final pendingProfileImage = Completer<http.Response>();
    const imagePath = '/v1/friends/test-friend/profile-image';
    final api = _fakeApi(
      hasTodayOutfit: false,
      respond: (request) {
        switch (request.url.path) {
          case '/v1/friends':
            return http.Response.bytes(
              utf8.encode(
                jsonEncode({
                  'friends': [
                    {
                      'friendId': 'test-friend',
                      'displayName': 'はると',
                      'profileImage': imagePath,
                      'today': published
                          ? {
                              'date': '2026-11-09',
                              'image': '/v1/friends/test-friend/today/image',
                              'liked': false,
                              'items': [],
                            }
                          : null,
                    },
                  ],
                }),
              ),
              200,
            );
          case '/v1/friends/requests':
            return http.Response('{"incoming":[],"outgoing":[]}', 200);
          case imagePath:
            expect(request.headers['Authorization'], 'Bearer tok');
            if (!published) privateProfileImageRequests++;
            if (holdProfileImage) return pendingProfileImage.future;
            return http.Response.bytes(_png, 200);
          default:
            return null;
        }
      },
    );
    await tester.pumpWidget(
      DfHackApp(auth: auth, api: api, ble: UnsupportedBleController()),
    );
    await tester.pumpAndSettle();
    final home = find.byType(HomeScreen);
    final avatar = find.descendant(
      of: home,
      matching: find.byType(FriendAvatar),
    );
    final name = find.descendant(of: home, matching: find.text('はると'));
    final profile = find.byType(FriendProfileScreen);
    final nav = find.byType(FloatingNavBar);
    final navElement = tester.element(nav);
    await tester.scrollUntilVisible(
      avatar.hitTestable(),
      170,
      scrollable: find
          .descendant(of: home, matching: find.byType(Scrollable))
          .first,
    );
    await tester.tap(avatar);
    await tester.pumpAndSettle();
    expect(profile, findsOneWidget);
    expect(tester.element(nav), same(navElement));
    expect(find.bySemanticsLabel('はるとの今日のコーデ'), findsOneWidget);

    await tester.tap(find.byTooltip('ホーム'));
    await tester.pumpAndSettle();
    published = false;
    await tester.tap(name);
    await tester.pumpAndSettle();
    expect(profile, findsOneWidget);
    expect(find.text('今日の公開コーデはありません'), findsOneWidget);
    expect(find.bySemanticsLabel('はるとの今日のコーデ'), findsNothing);
    final cropped = find.descendant(
      of: profile,
      matching: find.byType(CroppedProfileImage),
    );
    expect(cropped, findsOneWidget);
    expect(privateProfileImageRequests, greaterThan(0));

    await tester.runAsync(
      () => precacheImage(
        tester.widget<CroppedProfileImage>(cropped).image,
        tester.element(cropped),
      ),
    );
    await tester.pump();
    final rawImage = find.descendant(
      of: cropped,
      matching: find.byType(RawImage),
    );
    final displayed = tester.widget<RawImage>(rawImage).image;
    expect(displayed, isNotNull);
    holdProfileImage = true;
    await tester
        .widget<FriendProfileScreen>(profile)
        .activity!
        .refreshFriends();
    await tester.pumpAndSettle();
    expect(tester.widget<RawImage>(rawImage).image, same(displayed));
    pendingProfileImage.complete(http.Response.bytes(_png, 200));
    await tester.pumpAndSettle();
  });

  for (final entry in ['マイページ', '探す']) {
    testWidgets('$entryから撮影し、投稿の処理を開始したらホームに戻る', (tester) async {
      const channel = MethodChannel('jp.dfhack26.app/outfit_notifications');
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final jobs = _JobStream();
      final api = _fakeApi(hasTodayOutfit: false);
      final submission = OutfitSubmission(api, jobs: jobs);
      final auth = DevAuthService();
      addTearDown(() async {
        submission.dispose();
        auth.dispose();
        await jobs.controller.close();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: MainShell(
            auth: auth,
            api: api,
            ble: UnsupportedBleController(),
            submission: submission,
            onDarkModeChanged: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(entry));
      await tester.pumpAndSettle();
      final capture = entry == '探す'
          ? find.bySemanticsLabel('撮影する')
          : find.byTooltip('投稿');
      final camera = find.byType(OutfitCameraScreen);

      await tester.tap(capture);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(
        find.descendant(of: camera, matching: find.byTooltip('戻る')),
      );
      await tester.pumpAndSettle();
      expect(capture.hitTestable(), findsOneWidget);
      expect(submission.jobId, isNull);

      await tester.tap(capture);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.widget<OutfitCameraScreen>(camera).onPhotoConfirmed!(
        XFile.fromData(_png),
      );
      Navigator.of(tester.element(camera)).pop();
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Wearby').hitTestable(), findsOneWidget);
      expect(camera, findsNothing);
      expect(submission.processing, isTrue);

      jobs.controller.add(const OutfitJob(status: 'failed'));
      await tester.pumpAndSettle();
    });
  }

  testWidgets('処理完了から結果を開けて、登録後も画面上部で知らせる', (tester) async {
    const channel = MethodChannel('jp.dfhack26.app/outfit_notifications');
    final messenger = tester.binding.defaultBinaryMessenger;
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final jobs = _JobStream();
    final api = _fakeApi();
    final submission = OutfitSubmission(api, jobs: jobs);
    final auth = DevAuthService();
    addTearDown(() async {
      submission.dispose();
      auth.dispose();
      await jobs.controller.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: MainShell(
          auth: auth,
          api: api,
          ble: UnsupportedBleController(),
          submission: submission,
          onDarkModeChanged: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await submission.start('test-user', _png);
    jobs.controller.add(
      const OutfitJob(
        status: 'succeeded',
        outfitImage: '/v1/outfits/today/image',
      ),
    );
    await tester.pumpAndSettle();

    final banner = find.byType(AppBanner);
    expect(tester.getTopLeft(banner).dy, lessThan(48));
    expect(calls, isNot(contains('complete')));
    await tester.tap(find.text('結果を見る'));
    await tester.pumpAndSettle();
    expect(banner, findsNothing);
    expect(find.byType(ProcessedOutfitScreen), findsOneWidget);

    await tester.tap(find.text('コーデを投稿'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(banner).dy, lessThan(48));
    expect(find.text('今日のコーデを投稿しました'), findsOneWidget);
    expect(find.text('結果を見る'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);

    await tester.tap(find.byTooltip('通知を閉じる'));
    await tester.pumpAndSettle();
    expect(banner, findsNothing);
  });

  testWidgets('ログインすると、名前がある人はそのまま本体 (ホーム) に入る', (tester) async {
    final auth = DevAuthService();
    await tester.pumpWidget(
      DfHackApp(auth: auth, api: _fakeApi(), ble: UnsupportedBleController()),
    );
    expect(find.text('Google で続ける'), findsOneWidget);

    await tester.tap(find.text('Google で続ける'));
    await tester.pumpAndSettle();

    expect(auth.isSignedIn, isTrue);
    expect(find.bySemanticsLabel('Wearby'), findsOneWidget);
    expect(find.byTooltip('マイページ'), findsOneWidget);
  });

  testWidgets('コーデカレンダーの日付から写真と着用アイテムを確認できる', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.now();
    final date = DateTime(now.year, now.month, 8);
    final auth = DevAuthService();
    await auth.signInAnonymously();
    await tester.pumpWidget(
      DfHackApp(
        auth: auth,
        api: _fakeApi(outfitDate: date.toIso8601String().split('T').first),
        ble: UnsupportedBleController(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('マイページ'));
    await tester.pumpAndSettle();

    final recorded = find.bySemanticsLabel('${date.month}月8日のコーデ');
    await tester.ensureVisible(recorded);
    final thumbnail = find.descendant(
      of: recorded,
      matching: find.byType(Image),
    );
    final dayNumber = find.descendant(of: recorded, matching: find.text('8'));
    expect(tester.getCenter(dayNumber), tester.getCenter(thumbnail));
    await tester.tap(recorded);
    await tester.pumpAndSettle();
    expect(find.text('${date.year}年${date.month}月8日のコーデ'), findsOneWidget);
    expect(
      tester
          .widget<OutfitReviewBackground>(find.byType(OutfitReviewBackground))
          .image,
      isNotNull,
    );
    expect(find.text('クルーネックニット'), findsOneWidget);
    await tester.tap(find.text('アウター').last);
    await tester.pumpAndSettle();
    expect(find.text('ステンカラーコート'), findsOneWidget);
    expect(find.text('古着'), findsOneWidget);
    await tester.tap(find.byTooltip('戻る'));
    await tester.pumpAndSettle();

    final emptyDay = find.bySemanticsLabel('${date.month}月9日');
    expect(
      tester
          .getSemantics(emptyDay)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isFalse,
    );
    await tester.tap(emptyDay);
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('コーデカレンダー'), findsOneWidget);
  });

  testWidgets('設定の表示名を保存し、確認後に公開を停止してログアウトする', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final auth = DevAuthService();
    String? savedName;
    var unpublished = false;
    await tester.pumpWidget(
      DfHackApp(
        auth: auth,
        api: _fakeApi(
          onNameSaved: (name) => savedName = name,
          onUnpublish: () {
            expect(auth.isSignedIn, isTrue);
            unpublished = true;
          },
        ),
        ble: UnsupportedBleController(),
      ),
    );
    await tester.tap(find.text('Google で続ける'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('マイページ'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('設定'));
    await tester.pumpAndSettle();
    expect(find.text('マイページの画像'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  はる  ');
    await tester.pump();
    await tester.tap(find.text('表示名を保存'));
    await tester.pumpAndSettle();
    expect(savedName, 'はる');
    await tester.tap(find.byTooltip('通知を閉じる'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('戻る'));
    await tester.pumpAndSettle();
    expect(find.text('はる'), findsOneWidget);

    await tester.tap(find.byTooltip('設定'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('ログアウト'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ログアウト'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(auth.isSignedIn, isTrue);
    expect(unpublished, isFalse);

    await tester.tap(find.text('ログアウト'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('ログアウト'),
      ),
    );
    await tester.pumpAndSettle();
    expect(unpublished, isTrue);
    expect(auth.isSignedIn, isFalse);
    expect(find.text('Google で続ける'), findsOneWidget);
  });

  testWidgets('設定でダークモードを保存するとホームにも反映する', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final auth = DevAuthService();
    await auth.signInAnonymously();
    bool? saved;
    await tester.pumpWidget(
      DfHackApp(
        auth: auth,
        api: _fakeApi(),
        ble: UnsupportedBleController(),
        onSaveDarkMode: (enabled) async => saved = enabled,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('マイページ'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('設定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ダークモード'));
    await tester.pumpAndSettle();
    expect(saved, isTrue);
    expect(
      tester
          .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'ダークモード'))
          .value,
      isTrue,
    );
    await tester.tap(find.byTooltip('戻る'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('ホーム'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.bySemanticsLabel('Wearby'))).brightness,
      Brightness.dark,
    );
  });

  testWidgets('ホームの更新中や取得失敗時も表示中の内容を残す', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final auth = DevAuthService();
    await auth.signInAnonymously();
    Completer<void>? reload;
    var reloadStarted = false;
    await tester.pumpWidget(
      DfHackApp(
        auth: auth,
        api: _fakeApi(
          waitForMe: () async {
            final pending = reload;
            if (pending == null) return;
            reloadStarted = true;
            await pending.future;
          },
        ),
        ble: UnsupportedBleController(),
      ),
    );
    await tester.pumpAndSettle();
    final refresh = tester.state<RefreshIndicatorState>(
      find.byType(RefreshIndicator),
    );
    reload = Completer<void>();
    unawaited(refresh.show());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(reloadStarted, isTrue);
    expect(find.text('今日のコーデ'), findsOneWidget);
    expect(find.byType(AppLoadingScreen), findsNothing);

    reload.completeError(StateError('test refresh failed'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('ホームを更新できませんでした'), findsOneWidget);
    expect(find.text('今日のコーデ'), findsOneWidget);
  });

  testWidgets('名前が空なら名前の設定へ進む', (tester) async {
    final auth = DevAuthService();
    await tester.pumpWidget(
      DfHackApp(
        auth: auth,
        api: _fakeApi(meName: ''),
        ble: UnsupportedBleController(),
      ),
    );

    await tester.tap(find.text('Google で続ける'));
    await tester.pumpAndSettle();

    expect(find.text('アカウント名は？'), findsOneWidget);
  });

  testWidgets('ログインが復元されても、名前が空なら名前の設定へ進む', (tester) async {
    final auth = DevAuthService();
    await auth.signInAnonymously();
    await tester.pumpWidget(
      DfHackApp(
        auth: auth,
        api: _fakeApi(meName: ''),
        ble: UnsupportedBleController(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('アカウント名は？'), findsOneWidget);
  });

  testWidgets('探すの空表示では保護せず、着姿を出す前に保護する', (tester) async {
    const channel = MethodChannel('jp.dfhack26.app/viewer_security');
    final messenger = tester.binding.defaultBinaryMessenger;
    final protection = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      protection.add(call.method);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final auth = DevAuthService();
    await auth.signInAnonymously();
    var requests = 0;
    await tester.pumpWidget(
      DfHackApp(
        auth: auth,
        ble: UnsupportedBleController(),
        api: _fakeApi(
          nearby: () => {
            'viewerPublishing': true,
            'cards': [
              if (++requests > 1)
                {
                  'cardId': 'test-card',
                  'image': '/v1/cards/test-card/image',
                  'seenAgoSec': 180,
                  'expiresAt': DateTime.now()
                      .add(const Duration(minutes: 30))
                      .toIso8601String(),
                },
            ],
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('探す'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('近くのコーデはまだありません'), findsOneWidget);
    expect(find.text('ホームへ戻る'), findsNothing);
    expect(protection, isEmpty);

    await tester.tap(find.text('再確認'));
    await tester.pumpAndSettle();
    expect(find.text('3分前'), findsOneWidget);
    expect(protection, ['enable']);
    await tester.tap(find.byTooltip('戻る'));
    await tester.pumpAndSettle();
    expect(protection, ['enable', 'disable']);
  });

  testWidgets('未投稿なら模擬カードを取得せず撮影に案内する', (tester) async {
    final auth = DevAuthService();
    await auth.signInAnonymously();
    var requests = 0;
    await tester.pumpWidget(
      DfHackApp(
        auth: auth,
        ble: UnsupportedBleController(),
        api: _fakeApi(
          hasTodayOutfit: false,
          nearby: () {
            requests++;
            return {'viewerPublishing': true, 'cards': []};
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('探す'));
    await tester.pumpAndSettle();
    expect(requests, 0);
    expect(find.text('コーデを投稿して、\nみんなのを見よう。'), findsOneWidget);

    expect(find.text('撮影する'), findsNothing);
    await tester.tap(find.bySemanticsLabel('撮影する'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(OutfitCameraScreen), findsOneWidget);
  });

  testWidgets('非公開なら模擬カードを取得せず、公開すると表示する', (tester) async {
    const channel = MethodChannel('jp.dfhack26.app/viewer_security');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final auth = DevAuthService();
    await auth.signInAnonymously();
    var requests = 0;
    await tester.pumpWidget(
      DfHackApp(
        auth: auth,
        ble: UnsupportedBleController(),
        api: _fakeApi(
          isPublishing: false,
          nearby: () {
            requests++;
            return {
              'viewerPublishing': true,
              'cards': [
                {
                  'cardId': 'test-card',
                  'image': '/v1/cards/test-card/image',
                  'seenAgoSec': 180,
                  'expiresAt': DateTime.now()
                      .add(const Duration(minutes: 30))
                      .toIso8601String(),
                },
              ],
            };
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('探す'));
    await tester.pumpAndSettle();
    expect(requests, 0);
    expect(find.text('コーデを公開して、\nみんなのを見よう。'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('公開する'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('公開する'));
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(find.text('3分前'), findsOneWidget);
  });
}
