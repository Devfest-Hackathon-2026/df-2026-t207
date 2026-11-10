import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../lib/api/api_client.dart';
import '../../lib/api/api_models.dart';
import '../../lib/app/publishing_controller.dart';
import '../../lib/ble/ble_controller.dart';

/// 常駐の代わり。呼ばれた順を覚える。
class FakeBle implements BleController {
  FakeBle({this.supported = true, this.granted = true, this.grantOnRequest = true});

  bool supported;
  bool granted;
  bool grantOnRequest;
  bool failStart = false;
  final calls = <String>[];
  PublishState? started;
  List<Sighting> received = const [];
  final _status = StreamController<BleStatus>.broadcast();

  void emit(BleStatus s) => _status.add(s);

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<BlePermissions> permissions() async =>
      BlePermissions(bluetooth: granted, notification: granted);

  @override
  Future<BlePermissions> requestPermissions() async {
    calls.add('request');
    if (grantOnRequest) granted = true;
    return permissions();
  }

  @override
  Future<void> start(PublishState state, {bool transmit = true, bool receive = true}) async {
    calls.add('start');
    if (failStart) throw Exception('no bluetooth');
    started = state;
  }

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<List<Sighting>> sightings({Duration window = const Duration(minutes: 5)}) async =>
      received;

  @override
  Stream<BleStatus> get status => _status.stream;
}

String _example(String name) => File('../docs/api-examples/$name.json').readAsStringSync();

/// 届いたリクエストを (メソッド パス 本文) で覚える api
(ApiClient, List<String>) _api() {
  final seen = <String>[];
  final client = ApiClient(
    idToken: () async => 'tok',
    httpClient: MockClient((r) async {
      seen.add('${r.method} ${r.url.path} ${r.body}');
      final body = switch (r.url.path) {
        '/v1/publish' => (jsonDecode(r.body) as Map)['visibility'] == 'nearby'
            ? _example('publish')
            : '{"visibility":"private"}',
        '/v1/nearby' || '/v1/demo/nearby' => _example('nearby'),
        _ => throw StateError(r.url.path),
      };
      return http.Response.bytes(utf8.encode(body), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }),
  );
  return (client, seen);
}

void main() {
  test('公開すると、受け取った匿名 ID で常駐を始める', () async {
    final (api, seen) = _api();
    final ble = FakeBle();
    final c = PublishingController(api: api, ble: ble);
    await c.init();

    final state = await c.setPublishing(true);
    expect(state.isPublishing, isTrue);
    expect(seen.single, startsWith('PUT /v1/publish {"visibility":"nearby"}'));
    expect(ble.calls, ['start']);
    expect(ble.started!.broadcastIds.length, 3);
  });

  test('Bluetooth の許可が無ければ求め、断られたら公開しない', () async {
    final (api, seen) = _api();
    final ble = FakeBle(granted: false, grantOnRequest: false);
    final c = PublishingController(api: api, ble: ble);
    await c.init();

    await expectLater(c.setPublishing(true), throwsA(isA<PublishException>()));
    expect(ble.calls, ['request']);
    expect(seen, isEmpty);
  });

  test('常駐を始められなければ、サーバも非公開に戻す', () async {
    final (api, seen) = _api();
    final ble = FakeBle()..failStart = true;
    final c = PublishingController(api: api, ble: ble);
    await c.init();

    await expectLater(c.setPublishing(true), throwsException);
    expect(seen.map((s) => s.split(' {').last), [
      '"visibility":"nearby"}',
      '"visibility":"private"}',
    ]);
  });

  test('非公開にすると、常駐を止めてからサーバを非公開にする', () async {
    final (api, seen) = _api();
    final ble = FakeBle();
    final c = PublishingController(api: api, ble: ble);
    await c.init();

    final state = await c.setPublishing(false);
    expect(state.isPublishing, isFalse);
    expect(ble.calls, ['stop']);
    expect(seen.single, contains('"private"'));
  });

  test('BLE の無い所 (Web デモ) では常駐を呼ばず、近くのコーデは模擬の検出', () async {
    final (api, seen) = _api();
    final ble = FakeBle(supported: false);
    final c = PublishingController(api: api, ble: ble);
    await c.init();

    await c.setPublishing(true);
    expect(ble.calls, isEmpty);

    final nearby = await c.loadNearby();
    expect(seen.last, startsWith('POST /v1/demo/nearby'));
    expect(nearby.cards, isNotEmpty);
  });

  test('近くのコーデは、受け取った ID を送ってカードにする', () async {
    final (api, seen) = _api();
    final ble = FakeBle()
      ..received = [
        Sighting(id: 'aa' * 11, lastSeenAt: DateTime.utc(2026, 11, 8, 1), rssi: -60, txPower: -7),
      ];
    final c = PublishingController(api: api, ble: ble);
    await c.init();

    final nearby = await c.loadNearby();
    expect(seen.single, startsWith('POST /v1/nearby'));
    expect(seen.single, contains('"id":"${'aa' * 11}"'));
    expect(nearby.cards.first.items, isNotEmpty);
  });

  test('公開状態が分かっていて受信がない時は、その場で空を返す', () async {
    final (api, seen) = _api();
    final c = PublishingController(api: api, ble: FakeBle());
    await c.init();
    final nearby = await c.loadNearby(viewerPublishing: true);
    expect(nearby.cards, isEmpty);
    expect(nearby.viewerPublishing, isTrue);
    expect(seen, isEmpty);
  });

  test('サーバは公開中なのに常駐が止まっていたら始め直す', () async {
    final (api, _) = _api();
    final ble = FakeBle();
    final c = PublishingController(api: api, ble: ble);
    await c.init();
    final me = Me.fromJson(jsonDecode(_example('me')) as Map<String, dynamic>);

    expect(await c.resumeIfNeeded(me), isNotNull);
    expect(ble.calls, ['start']);

    ble.emit(const BleStatus(running: true));
    await Future<void>.delayed(Duration.zero);
    expect(await c.resumeIfNeeded(me), isNull);
    expect(ble.calls, ['start']);
  });

  test('Bluetooth がオフの時は注意を出す', () async {
    final (api, _) = _api();
    final ble = FakeBle();
    final c = PublishingController(api: api, ble: ble);
    await c.init();

    ble.emit(const BleStatus(running: true, error: 'bluetooth_off'));
    await Future<void>.delayed(Duration.zero);
    expect(c.notice, contains('Bluetooth がオフ'));
  });

  test('検出エラーの詳細を表示せず再試行を案内する', () async {
    final (api, _) = _api();
    final ble = FakeBle();
    final c = PublishingController(api: api, ble: ble);
    await c.init();

    ble.emit(const BleStatus(running: true, error: 'internal exception detail'));
    await Future<void>.delayed(Duration.zero);
    expect(c.notice, 'すれ違いの検出を始められませんでした。設定を確認してもう一度お試しください');
    expect(c.notice, isNot(contains('internal exception detail')));
  });
}
