import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/api_models.dart';
import '../ble/ble_controller.dart';

class PublishException implements Exception {
  PublishException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 今日の公開と、すれ違いの検出 (BLE の常駐) をまとめて扱う (tasks の A5)。
///
/// - 公開: `PUT /v1/publish` で匿名 ID の並びを受け取り、常駐に渡して発信と受信を始める
/// - 非公開: 常駐を止めてから `PUT /v1/publish` を private にする
/// - 24 時に切れるのは常駐が自分で行う
/// - 近くのコーデ: 受け取った ID を `POST /v1/nearby` に送る。BLE の無い所 (Web デモ) は模擬の検出
class PublishingController extends ChangeNotifier {
  PublishingController({required this.api, required this.ble});

  final ApiClient api;
  final BleController ble;

  bool _supported = false;
  BlePermissions _permissions = const BlePermissions(bluetooth: false, notification: false);
  BleStatus _status = const BleStatus();
  StreamSubscription<BleStatus>? _sub;

  /// この端末で BLE の検出が使えるか (Web デモでは false)
  bool get supported => _supported;
  BlePermissions get permissions => _permissions;
  BleStatus get status => _status;

  Future<void> init() async {
    try {
      _supported = await ble.isSupported();
    } catch (_) {
      _supported = false;
    }
    if (_supported) {
      _permissions = await ble.permissions();
      _sub = ble.status.listen((s) {
        _status = s;
        notifyListeners();
      });
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<BlePermissions> requestPermissions() async {
    if (!_supported) return _permissions;
    _permissions = await ble.requestPermissions();
    notifyListeners();
    return _permissions;
  }

  /// 公開を切り替え、新しい公開の状態を返す。失敗したら例外 (画面が知らせて元に戻す)。
  Future<PublishState> setPublishing(bool publish) async {
    if (!publish) {
      if (_supported) {
        try {
          await ble.stop();
        } catch (_) {
          // 常駐が止まっていなくても、サーバは非公開にする (ID はもう着姿に変わらない)
        }
      }
      return api.setPublishing(false);
    }

    if (_supported && !_permissions.bluetooth) {
      await requestPermissions();
      if (!_permissions.bluetooth) {
        throw PublishException('Bluetooth の許可が無いため公開できません');
      }
    }
    final state = await api.setPublishing(true);
    if (_supported) {
      try {
        await ble.start(state);
      } catch (e) {
        // 発信できないのに公開中にしない
        try {
          await api.setPublishing(false);
        } catch (_) {}
        rethrow;
      }
    }
    return state;
  }

  /// サーバでは公開中なのに常駐が動いていない時 (入れ直した後など) に、ID を取り直して始め直す。
  Future<PublishState?> resumeIfNeeded(Me me) async {
    if (!_supported || !me.publishing.isPublishing || !_permissions.bluetooth) return null;
    if (_status.running) return null;
    try {
      return await setPublishing(true);
    } catch (_) {
      return null;
    }
  }

  /// 画面に出す注意。無ければ null
  String? get notice {
    if (!_supported || !_status.running) return null;
    final e = _status.error;
    if (e == null) return null;
    if (e == 'bluetooth_off') return 'Bluetooth がオフです。オンにすると発信を再開します。';
    return 'すれ違いの検出を始められませんでした。設定を確認してもう一度お試しください';
  }

  /// 近くのコーデ (A2 の画面が使う)。BLE の無い所は模擬の検出 (Web デモ)。
  Future<NearbyResult> loadNearby({bool? viewerPublishing}) async {
    if (!_supported) return api.demoNearby();
    final sightings = await ble.sightings();
    final payload = nearbySightingsJson(sightings);
    if (payload.isEmpty && viewerPublishing != null) {
      return NearbyResult(cards: const [], viewerPublishing: viewerPublishing);
    }
    return api.nearby(payload);
  }
}
