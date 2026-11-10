import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../mypage/profile_photo.dart';

Future<File> _fileFor(String uid) async {
  final directory = await getApplicationSupportDirectory();
  return File('${directory.path}/profile-${Uri.encodeComponent(uid)}.image');
}

Future<ProfilePhoto?> loadProfilePhoto(String uid) async {
  final file = await _fileFor(uid);
  if (!await file.exists()) return null;
  final bytes = await file.readAsBytes();
  if (bytes.isEmpty) return null;
  // 以前の Android 版は、同じ場所に画像のバイト列だけを保存していた。
  return bytes.first == 0x7b
      ? ProfilePhoto.decode(utf8.decode(bytes))
      : ProfilePhoto(bytes);
}

Future<void> saveProfilePhoto(String uid, ProfilePhoto? photo) async {
  final file = await _fileFor(uid);
  if (photo == null) {
    if (await file.exists()) await file.delete();
    return;
  }
  await _writeFile(file, utf8.encode(photo.encode()));
}

Future<File> _appearanceFile() async {
  final directory = await getApplicationSupportDirectory();
  return File('${directory.path}/dark-mode');
}

Future<bool> loadDarkMode() async {
  final file = await _appearanceFile();
  return await file.exists() && await file.readAsString() == '1';
}

Future<void> saveDarkMode(bool enabled) async =>
    _writeFile(await _appearanceFile(), utf8.encode(enabled ? '1' : '0'));

Future<File> _demoModeFile() async {
  final directory = await getApplicationSupportDirectory();
  return File('${directory.path}/demo-mode');
}

/// デモモード (lib/app/demo_mode.dart)。切り替えたことが無ければ [fallback]
Future<bool> loadDemoMode({required bool fallback}) async {
  final file = await _demoModeFile();
  return await file.exists() ? await file.readAsString() == '1' : fallback;
}

Future<void> saveDemoMode(bool enabled) async =>
    _writeFile(await _demoModeFile(), utf8.encode(enabled ? '1' : '0'));

Future<void> _writeFile(File file, List<int> bytes) async {
  final temporary = File('${file.path}.tmp');
  try {
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(file.path);
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}
