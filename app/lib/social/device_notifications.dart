import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';

import '../api/api_client.dart';

class DeviceNotifications {
  DeviceNotifications({
    required this.api,
    required this.onRefresh,
    required this.onOpen,
    required this.onRegistered,
  });

  final ApiClient api;
  final void Function() onRefresh;
  final void Function(Map<String, dynamic>) onOpen;
  final void Function(bool) onRegistered;
  final _messaging = FirebaseMessaging.instance;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  Future<void> _registration = Future.value();
  String? _token;
  bool _active = true;
  bool _listening = false;
  bool _allowed = false;

  Future<void> start() async {
    if (!_listening) {
      _listening = true;
      _subscriptions.addAll([
        FirebaseMessaging.onMessage.listen((_) => onRefresh()),
        FirebaseMessaging.onMessageOpenedApp.listen(
          (message) => onOpen(message.data),
        ),
        // API は Firebase Installation ID ではなく FCM トークンを受け取る。
        // ignore: deprecated_member_use
        _messaging.onTokenRefresh.listen((token) {
          if (_allowed) unawaited(_register(token));
        }),
      ]);
    }
    try {
      final settings = await _messaging.requestPermission();
      _allowed = settings.authorizationStatus == AuthorizationStatus.authorized;
      if (_allowed) {
        // ignore: deprecated_member_use
        final token = await _messaging.getToken();
        if (token != null) await _register(token);
      }
    } catch (_) {
      // アプリ内の通知は端末の登録に失敗しても利用できる。
    }
    try {
      final initial = await _messaging.getInitialMessage();
      if (_active && initial != null) onOpen(initial.data);
    } catch (_) {
      // アプリ内の通知一覧から開ける。
    }
  }

  Future<void> _register(String token) {
    if (!_active) return Future.value();
    _registration = _registration.then((_) async {
      if (!_active || _token == token) return;
      final previous = _token;
      try {
        await api.setDeviceToken(token, enabled: true);
        _token = token;
        if (_active) onRegistered(true);
        if (previous != null) {
          await api.setDeviceToken(previous, enabled: false);
        }
      } catch (_) {
        if (_active) onRegistered(_token != null);
      }
    });
    return _registration;
  }

  Future<void> unregister() async {
    _active = false;
    await _registration;
    try {
      // ignore: deprecated_member_use
      final token = _token ?? await _messaging.getToken();
      if (token != null) await api.setDeviceToken(token, enabled: false);
      _token = null;
      onRegistered(false);
    } catch (_) {
      _active = true;
      rethrow;
    }
  }

  void dispose() {
    _active = false;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
  }
}
