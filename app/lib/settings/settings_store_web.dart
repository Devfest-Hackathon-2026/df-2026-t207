import 'package:web/web.dart' as web;

import '../mypage/profile_photo.dart';

String _keyFor(String uid) => 'df-hack26.profile-photo.$uid';
const _darkModeKey = 'df-hack26.dark-mode';

Future<bool> loadDarkMode() async =>
    web.window.localStorage.getItem(_darkModeKey) == '1';

Future<void> saveDarkMode(bool enabled) async =>
    web.window.localStorage.setItem(_darkModeKey, enabled ? '1' : '0');

/// Web デモは常にデモモード (切り替えない)
Future<bool> loadDemoMode({required bool fallback}) async => fallback;

Future<void> saveDemoMode(bool enabled) async {}

Future<ProfilePhoto?> loadProfilePhoto(String uid) async {
  final value = web.window.localStorage.getItem(_keyFor(uid));
  return value == null ? null : ProfilePhoto.decode(value);
}

Future<void> saveProfilePhoto(String uid, ProfilePhoto? photo) async {
  final storage = web.window.localStorage;
  final key = _keyFor(uid);
  if (photo == null) {
    storage.removeItem(key);
  } else {
    storage.setItem(key, photo.encode());
  }
}
