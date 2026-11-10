import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../api/api_models.dart';

/// 受け取った匿名 ID 1 つ (端末のメモリに直近 5 分だけある)。
class Sighting {
  const Sighting({
    required this.id,
    required this.lastSeenAt,
    required this.rssi,
    required this.txPower,
  });

  factory Sighting.fromChannel(Map<Object?, Object?> m) => Sighting(
        id: m['id']! as String,
        lastSeenAt: DateTime.fromMillisecondsSinceEpoch((m['lastSeenMs']! as num).toInt()),
        rssi: (m['rssi']! as num).toInt(),
        txPower: (m['txPower']! as num).toInt(),
      );

  /// 11 バイトの 16 進 (22 文字)
  final String id;
  final DateTime lastSeenAt;

  /// 受信の強さ (dBm)。保持している間で一番強かった値
  final int rssi;

  /// 発信に載っていた送信の強さ (dBm)
  final int txPower;
}

/// `POST /v1/nearby` の `sightings` の形にする。
///
/// 電波の強さは門にしないが、明らかに弱い物 (既定 -90 dBm より弱い) だけは外す
/// (docs/tech-decisions.md の 3 節)。新しい順で、上限は 200 件。
List<Map<String, Object>> nearbySightingsJson(
  List<Sighting> sightings, {
  int minRssi = -90,
}) {
  final kept = sightings.where((s) => s.rssi >= minRssi).toList()
    ..sort((a, b) => b.lastSeenAt.compareTo(a.lastSeenAt));
  return [
    for (final s in kept.take(200))
      {
        'id': s.id,
        'lastSeenAt': s.lastSeenAt.toUtc().toIso8601String(),
        'rssi': s.rssi,
        'txPower': s.txPower,
      },
  ];
}

class BlePermissions {
  const BlePermissions({required this.bluetooth, required this.notification});

  factory BlePermissions.fromChannel(Map<Object?, Object?>? m) => BlePermissions(
        bluetooth: m?['bluetooth'] == true,
        notification: m?['notification'] == true,
      );

  final bool bluetooth;
  final bool notification;
}

class BleStatus {
  const BleStatus({
    this.running = false,
    this.transmitting = false,
    this.receiving = false,
    this.error,
  });

  factory BleStatus.fromChannel(Map<Object?, Object?>? m) => BleStatus(
        running: m?['running'] == true,
        transmitting: m?['transmitting'] == true,
        receiving: m?['receiving'] == true,
        error: m?['error'] as String?,
      );

  final bool running;
  final bool transmitting;
  final bool receiving;

  /// 例 bluetooth_off、advertise_FEATURE_UNSUPPORTED。無ければ null
  final String? error;
}

/// すれ違いの検出 (BLE の常駐) の窓口。Android は Kotlin の常駐サービス (app/android の ble/) につなぐ。
///
/// 公開している間だけ、匿名 ID の発信と近くの人の ID の受信を続ける (お互いさま)。
abstract class BleController {
  /// この端末で使えるか (Web やエミュレータでは false)
  Future<bool> isSupported();

  Future<BlePermissions> permissions();

  /// Bluetooth (と Android 13 以上なら通知) の許可を求める
  Future<BlePermissions> requestPermissions();

  /// 公開を始める。`PUT /v1/publish` で受け取った匿名 ID の並びを渡す。
  /// 端末はその時刻の枠の ID を発信し、`until` (その日の 24 時) に自分で止まる。
  Future<void> start(PublishState state, {bool transmit = true, bool receive = true});

  Future<void> stop();

  /// 直近 [window] に受け取った ID (新しい順)
  Future<List<Sighting>> sightings({Duration window = const Duration(minutes: 5)});

  Stream<BleStatus> get status;

  /// Android なら常駐につなぐ物、それ以外 (Web デモ) は何もしない物
  factory BleController.platform() =>
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
          ? MethodChannelBleController()
          : UnsupportedBleController();
}

class MethodChannelBleController implements BleController {
  MethodChannelBleController();

  final _method = const MethodChannel('jp.dfhack26.app/ble');
  final _events = const EventChannel('jp.dfhack26.app/ble/status');

  @override
  Future<bool> isSupported() async {
    final m = await _method.invokeMapMethod<Object?, Object?>('capabilities');
    return m?['supported'] == true;
  }

  @override
  Future<BlePermissions> permissions() async =>
      BlePermissions.fromChannel(await _method.invokeMapMethod<Object?, Object?>('permissions'));

  @override
  Future<BlePermissions> requestPermissions() async => BlePermissions.fromChannel(
        await _method.invokeMapMethod<Object?, Object?>('requestPermissions'),
      );

  @override
  Future<void> start(PublishState state, {bool transmit = true, bool receive = true}) async {
    final until = state.until;
    if (!state.isPublishing || until == null || state.broadcastIds.isEmpty) {
      throw ArgumentError('公開中で、匿名 ID と切れる時刻がある状態を渡す');
    }
    await _method.invokeMethod<void>('start', {
      'slots': [
        for (final b in state.broadcastIds)
          {'slotStart': b.slotStart.millisecondsSinceEpoch, 'id': b.id},
      ],
      'untilMs': until.millisecondsSinceEpoch,
      'transmit': transmit,
      'receive': receive,
    });
  }

  @override
  Future<void> stop() => _method.invokeMethod<void>('stop');

  @override
  Future<List<Sighting>> sightings({Duration window = const Duration(minutes: 5)}) async {
    final list = await _method.invokeListMethod<Object?>(
      'sightings',
      {'windowMs': window.inMilliseconds},
    );
    return [for (final m in list ?? const []) Sighting.fromChannel(m! as Map<Object?, Object?>)];
  }

  @override
  Stream<BleStatus> get status => _events
      .receiveBroadcastStream()
      .map((e) => BleStatus.fromChannel(e as Map<Object?, Object?>?));
}

/// Web デモなど、BLE の無い所。検出は Web デモの模擬 (`POST /v1/demo/nearby`) で代わりにする。
class UnsupportedBleController implements BleController {
  @override
  Future<bool> isSupported() async => false;

  @override
  Future<BlePermissions> permissions() async =>
      const BlePermissions(bluetooth: false, notification: false);

  @override
  Future<BlePermissions> requestPermissions() => permissions();

  @override
  Future<void> start(PublishState state, {bool transmit = true, bool receive = true}) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<List<Sighting>> sightings({Duration window = const Duration(minutes: 5)}) async =>
      const [];

  @override
  Stream<BleStatus> get status => Stream.value(const BleStatus());
}
