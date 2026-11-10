import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lib/api/api_models.dart';
import '../../lib/ble/ble_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('jp.dfhack26.app/ble');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'permissions':
          return {'bluetooth': true, 'notification': false};
        case 'sightings':
          return [
            {'id': 'aa' * 11, 'lastSeenMs': 1000, 'rssi': -60, 'txPower': -7},
          ];
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('公開の状態から、枠の始まりと ID と切れる時刻を常駐に渡す', () async {
    final state = PublishState(
      visibility: 'nearby',
      until: DateTime.utc(2026, 11, 8, 15),
      broadcastIds: [
        BroadcastId(slotStart: DateTime.utc(2026, 11, 8, 1, 15), id: '3fa91c0e7b2d4a8c61e5f0'),
      ],
    );
    await MethodChannelBleController().start(state);

    expect(calls.single.method, 'start');
    final args = calls.single.arguments as Map;
    expect(args['untilMs'], DateTime.utc(2026, 11, 8, 15).millisecondsSinceEpoch);
    expect(args['slots'], [
      {
        'slotStart': DateTime.utc(2026, 11, 8, 1, 15).millisecondsSinceEpoch,
        'id': '3fa91c0e7b2d4a8c61e5f0',
      },
    ]);
    expect(args['transmit'], isTrue);
    expect(args['receive'], isTrue);
  });

  test('非公開や ID の無い状態では始めない', () async {
    expect(
      () => MethodChannelBleController().start(const PublishState(visibility: 'private')),
      throwsArgumentError,
    );
    expect(calls, isEmpty);
  });

  test('許可と受け取った ID を読める', () async {
    final c = MethodChannelBleController();
    final p = await c.permissions();
    expect(p.bluetooth, isTrue);
    expect(p.notification, isFalse);

    final s = await c.sightings();
    expect(calls.last.arguments, {'windowMs': 5 * 60 * 1000});
    expect(s.single.id, 'aa' * 11);
    expect(s.single.rssi, -60);
  });

  test('近くのコーデに送る形: 弱すぎる物を外し、新しい順', () {
    final json = nearbySightingsJson([
      Sighting(id: 'aa' * 11, lastSeenAt: DateTime.utc(2026, 1, 1, 0, 1), rssi: -70, txPower: -7),
      Sighting(id: 'bb' * 11, lastSeenAt: DateTime.utc(2026, 1, 1, 0, 3), rssi: -95, txPower: -7),
      Sighting(id: 'cc' * 11, lastSeenAt: DateTime.utc(2026, 1, 1, 0, 2), rssi: -88, txPower: 1),
    ]);
    expect(json.map((j) => j['id']), ['cc' * 11, 'aa' * 11]);
    expect(json.first['lastSeenAt'], '2026-01-01T00:02:00.000Z');
    expect(json.first['txPower'], 1);
  });
}
