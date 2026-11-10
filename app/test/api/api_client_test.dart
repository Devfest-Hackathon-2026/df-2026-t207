import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app/api/api_client.dart';
import 'package:app/api/api_models.dart';

/// docs/api-examples の見本をそのまま返す。
String _example(String name) =>
    File('../docs/api-examples/$name.json').readAsStringSync();

http.Response _json(String body, [int status = 200]) => http.Response.bytes(
  utf8.encode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  testWidgets('着用画像の表示用だけ英字の帯の高さを切り取る', (tester) async {
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder)
          .drawColor(const ui.Color(0xff000000), ui.BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(480, 600);
      picture.dispose();
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      image.dispose();
      final api = ApiClient(
        idToken: () async => 'tok',
        httpClient: MockClient(
          (_) async => http.Response.bytes(
            png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
            200,
          ),
        ),
      );
      const path = '/v1/tryon/t_preview/image';

      Future<(int, int)> sizeOf(ImageProvider provider) async {
        final stream = provider.resolve(ImageConfiguration.empty);
        final size = Completer<(int, int)>();
        final listener = ImageStreamListener((info, _) {
          size.complete((info.image.width, info.image.height));
          info.dispose();
        }, onError: size.completeError);
        stream.addListener(listener);
        try {
          return await size.future;
        } finally {
          stream.removeListener(listener);
        }
      }

      expect(await sizeOf(api.image(path)), (480, 600));
      expect(await sizeOf(api.tryOnImage(path)), (480, 560));
    });
  });

  test('ID トークンを Bearer で付け、見本の Me を読める', () async {
    late http.Request seen;
    final api = ApiClient(
      idToken: () async => 'tok',
      baseUrl: 'https://api.example/',
      httpClient: MockClient((r) async {
        seen = r;
        return _json(_example('me'));
      }),
    );

    final me = await api.getMe();
    expect(seen.url.toString(), 'https://api.example/v1/me');
    expect(seen.headers['Authorization'], 'Bearer tok');
    expect(me.displayName, 'りお');
    expect(me.viewCountToday, 3);
    expect(me.publishing.isPublishing, isTrue);
  });

  test('今日のコーデと手持ちの見本を読める', () async {
    final api = ApiClient(
      idToken: () async => 'tok',
      httpClient: MockClient(
        (r) async => _json(
          _example(r.url.path == '/v1/wardrobe' ? 'wardrobe' : 'today-outfit'),
        ),
      ),
    );

    final today = await api.getTodayOutfit();
    expect(today!.items.map((i) => i.slot), ['top', 'top', 'outer']);
    expect(today.items.last.memo, '古着');
    expect((await api.getWardrobe()).length, 6);
  });

  test('通知の既読、端末登録、服の保存は本番のリクエスト形式を使う', () async {
    final requests = <List<Object?>>[];
    final api = ApiClient(
      idToken: () async => 'test-token',
      httpClient: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer test-token');
        requests.add([
          request.method,
          request.url.path,
          request.body.isEmpty ? null : jsonDecode(request.body),
        ]);
        if (request.url.path == '/v1/saves' && request.method == 'POST') {
          return _json(
            '{"saveId":"s_item","slot":"top","label":"シャツ","source":"friend","savedAt":"2026-11-09T09:00:00+09:00"}',
            201,
          );
        }
        return http.Response('', 204);
      }),
    );

    final saved = await api.saveFriendItem('friend_1', 0);
    await api.deleteSave(saved.id);
    await api.readNotifications(['notice_1']);
    await api.readNotifications();
    await api.setDeviceToken('fcm-token', enabled: true);
    await api.setDeviceToken('fcm-token', enabled: false);

    expect(requests, [
      [
        'POST',
        '/v1/saves',
        {'friendId': 'friend_1', 'index': 0},
      ],
      ['DELETE', '/v1/saves/s_item', null],
      [
        'POST',
        '/v1/notifications/read',
        {
          'ids': ['notice_1'],
        },
      ],
      ['POST', '/v1/notifications/read', <String, Object>{}],
      [
        'PUT',
        '/v1/me/devices',
        {'token': 'fcm-token'},
      ],
      [
        'DELETE',
        '/v1/me/devices',
        {'token': 'fcm-token'},
      ],
    ]);
  });

  test('投稿写真はvisionに送り、同じ服の選択を本登録に渡す', () async {
    final api = ApiClient(
      idToken: () async => 'token',
      baseUrl: 'https://api.example',
      visionBaseUrl: 'https://vision.example/',
      httpClient: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer token');
        switch (request.url.path) {
          case '/v1/outfits/process':
            expect(request.url.host, 'vision.example');
            expect(request.method, 'POST');
            expect(
              request.headers['content-type'],
              startsWith('multipart/form-data;'),
            );
            final multipart = latin1.decode(request.bodyBytes);
            expect(multipart, contains('name="jobId"\r\n\r\njob_example'));
            expect(multipart, contains('name="photo"; filename="photo.jpg"'));
            return _json('{"jobId":"job_example","status":"succeeded"}');
          case '/v1/jobs/job_example/same-items':
            expect(request.url.host, 'api.example');
            expect(request.method, 'GET');
            final items = jsonDecode(_example('wardrobe'))['items'] as List;
            return _json(
              jsonEncode({
                'items': [
                  {'index': 2, 'wardrobeItem': items.first},
                ],
              }),
            );
          case '/v1/outfits/today':
            expect(request.url.host, 'api.example');
            expect(request.method, 'PUT');
            expect(jsonDecode(request.body), {
              'jobId': 'job_example',
              'items': [
                {'index': 2, 'memo': '手持ち', 'sameAs': 'w_existing'},
              ],
            });
            return _json(_example('today-outfit'));
          default:
            throw StateError('Unexpected path ${request.url.path}');
        }
      }),
    );
    expect(
      await api.processOutfit('job_example', Uint8List.fromList([255, 216])),
      'succeeded',
    );
    expect((await api.sameItems('job_example')).single.index, 2);
    final registered = await api.registerTodayOutfit(
      'job_example',
      [(index: 2, memo: '手持ち')],
      sameAs: {2: 'w_existing'},
    );
    expect(registered.items, isNotEmpty);
  });

  test('選んだカードと手持ちを照合・着用イメージへ渡す', () async {
    final api = ApiClient(
      idToken: () async => 'token',
      httpClient: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer token');
        switch (request.url.path) {
          case '/v1/match':
            expect(request.method, 'POST');
            expect(jsonDecode(request.body), {
              'cardId': 'card',
              'cardItemId': 'item',
            });
            return _json(_example('match'));
          case '/v1/me/photo':
            if (request.method == 'PUT') {
              final multipart = latin1.decode(request.bodyBytes);
              expect(multipart, contains('name="capturedWith"\r\n\r\ncamera'));
              expect(multipart, contains('name="photo"; filename="photo.jpg"'));
            } else {
              expect(request.method, 'DELETE');
            }
            return http.Response('', 204);
          case '/v1/tryon':
            expect(request.method, 'POST');
            expect(jsonDecode(request.body), {
              'cardId': 'card',
              'cardItemId': 'item',
              'wardrobeItemIds': ['w_existing'],
              'regenerate': true,
            });
            return _json(_example('tryon'));
          default:
            throw StateError('Unexpected path ${request.url.path}');
        }
      }),
    );
    expect((await api.match('card', 'item')).combos, isNotEmpty);
    await api.putTryOnPhoto(Uint8List.fromList([255, 216]));
    final image = await api.tryOn('card', 'item', [
      'w_existing',
    ], regenerate: true);
    expect(image.image, startsWith('/v1/tryon/'));
    expect(image.label, 'AI による着用イメージ');
    await api.deleteTryOnPhoto();
  });

  test('今日のコーデが無い (404) 時は null', () async {
    final api = ApiClient(
      idToken: () async => 'tok',
      httpClient: MockClient((_) async => http.Response('', 404)),
    );
    expect(await api.getTodayOutfit(), isNull);
  });

  test('公開の切り替えで visibility を送り、匿名 ID を受け取る', () async {
    late Map<String, dynamic> body;
    final api = ApiClient(
      idToken: () async => 'tok',
      httpClient: MockClient((r) async {
        expect(r.method, 'PUT');
        body = jsonDecode(r.body) as Map<String, dynamic>;
        return _json(_example('publish'));
      }),
    );

    final state = await api.setPublishing(true);
    expect(body, {'visibility': 'nearby'});
    expect(state.isPublishing, isTrue);
    expect(state.broadcastIds.first.id, '3fa91c0e7b2d4a8c61e5f0');
  });

  test('エラーは code と message を持つ例外にする', () async {
    final api = ApiClient(
      idToken: () async => 'tok',
      httpClient: MockClient((_) async => _json(_example('error-quota'), 429)),
    );
    expect(
      api.getMe(),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 429)
            .having((e) => e.code, 'code', 'quota_exceeded'),
      ),
    );
  });
}
