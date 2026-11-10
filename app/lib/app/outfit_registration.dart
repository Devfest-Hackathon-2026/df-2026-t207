import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../register/outfit_job.dart';
import '../register/outfit_registration_flow.dart';

/// 登録まで行かずに閉じた時 (戻った・撮りなおす)。カメラの画面はこれを受けて写真の確認に残る
class OutfitNotRegistered implements Exception {
  const OutfitNotRegistered();
}

/// カメラの「投稿」(`OutfitCameraScreen.onPhotoConfirmed`) から呼ぶ。
/// 処理 → 確かめる → 登録の画面を開き、登録できたら返る。できなければ [OutfitNotRegistered] を投げる。
Future<void> registerOutfitPhoto(
  BuildContext context, {
  required ApiClient api,
  required OutfitJobSource jobs,
  required Future<String> Function() uid,
  required XFile photo,
}) async {
  final bytes = await photo.readAsBytes();
  if (!context.mounted) throw const OutfitNotRegistered();
  final registered = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => OutfitRegistrationFlow(api: api, jobs: jobs, uid: uid, photo: bytes),
    ),
  );
  if (registered != true) throw const OutfitNotRegistered();
}
