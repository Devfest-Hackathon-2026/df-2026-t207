import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/api_models.dart';

/// 全身写真の処理の状況 (Firestore の `users/{uid}/jobs/{jobId}`、docs/api.yaml の `Job`)。
/// `vision` が書き、アプリは読むだけ。
class OutfitJob {
  const OutfitJob({
    required this.status,
    this.progress = 0,
    this.errorCode,
    this.errorMessage,
    this.outfitImage,
    this.items = const [],
  });

  factory OutfitJob.fromJson(Map<String, dynamic> j) {
    final error = j['error'] as Map?;
    final result = j['result'] as Map?;
    return OutfitJob(
      status: j['status'] as String? ?? 'queued',
      progress: (j['progress'] as num?)?.toDouble() ?? 0,
      errorCode: error?['code'] as String?,
      errorMessage: error?['message'] as String?,
      outfitImage: result?['outfitImage'] as String?,
      items: [
        for (final i in (result?['items'] as List? ?? const []))
          OutfitJobItem.fromJson(Map<String, dynamic>.from(i as Map)),
      ],
    );
  }

  /// queued / masking / segmenting / detecting / cutting / succeeded / failed
  final String status;
  final double progress;
  final String? errorCode;
  final String? errorMessage;

  /// 処理後の着姿の画像の口 (`/v1/jobs/{jobId}/images/outfit`)
  final String? outfitImage;
  final List<OutfitJobItem> items;

  bool get succeeded => status == 'succeeded';
  bool get failed => status == 'failed';
  bool get isDone => succeeded || failed;

  /// 処理中の画面に出す、今していること
  String get stepLabel => switch (status) {
    'queued' => '写真を送っています',
    'masking' => '顔と背景を消しています',
    'segmenting' || 'detecting' => '服を探しています',
    'cutting' => '服を切り抜いています',
    _ => '仕上げています',
  };
}

/// 処理の結果の服 1 着
class OutfitJobItem {
  const OutfitJobItem({
    required this.index,
    required this.image,
    required this.slot,
    required this.label,
    this.color,
  });

  factory OutfitJobItem.fromJson(Map<String, dynamic> j) => OutfitJobItem(
    index: (j['index'] as num).toInt(),
    image: j['image'] as String,
    slot: j['slot'] as String? ?? '',
    label: j['label'] as String? ?? '',
    color: j['color'] as String?,
  );

  final int index;

  /// 切り抜きの画像の口 (`/v1/jobs/{jobId}/images/item-<index>`)
  final String image;
  final String slot;
  final String label;
  final String? color;
}

/// jobs の文書を見る口。本物は Firestore、試験では差し替える。
abstract class OutfitJobSource {
  /// まだ文書が無い間は null が流れる
  Stream<OutfitJob?> watch(String uid, String jobId);
}

class FirestoreOutfitJobSource implements OutfitJobSource {
  FirestoreOutfitJobSource([FirebaseFirestore? db]) : _db = db;

  final FirebaseFirestore? _db;

  @override
  Stream<OutfitJob?> watch(String uid, String jobId) =>
      (_db ?? FirebaseFirestore.instance)
          .doc('users/$uid/jobs/$jobId')
          .snapshots()
          .map((s) => s.exists ? OutfitJob.fromJson(s.data()!) : null);
}

/// 処理が失敗した時。[message] は画面にそのまま出せる文
class OutfitJobException implements Exception {
  const OutfitJobException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'OutfitJobException($code)';
}

/// アプリが作る jobId (api.yaml の `^[A-Za-z0-9_-]{8,64}$`)
String newJobId([Random? random]) {
  const chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  final r = random ?? Random.secure();
  return 'job_${List.generate(20, (_) => chars[r.nextInt(chars.length)]).join()}';
}

/// 全身写真を vision に送り、jobs の文書で進み具合を知らせ、終わった jobs を返す。
///
/// 送る前に購読を始める (api.yaml の決まり)。vision の応答の後も文書の最後の書き込みが届くのを少し待つ。
/// 失敗は [OutfitJobException] で投げる。
Future<({String jobId, OutfitJob job})> runOutfitJob({
  required ApiClient api,
  required OutfitJobSource jobs,
  required String uid,
  required Uint8List photo,
  void Function(OutfitJob job)? onProgress,
  String? jobId,
  Duration settle = const Duration(seconds: 15),
}) async {
  final id = jobId ?? newJobId();
  OutfitJob? latest;
  final done = Completer<OutfitJob>();
  final sub = jobs.watch(uid, id).listen(
    (job) {
      if (job == null) return;
      latest = job;
      onProgress?.call(job);
      if (job.isDone && !done.isCompleted) done.complete(job);
    },
    onError: (Object _) {}, // 購読が切れても、vision の応答と最後の待ちで決める
  );
  try {
    try {
      await api.processOutfit(id, photo).timeout(const Duration(minutes: 4));
    } on ApiException catch (e) {
      throw OutfitJobException(e.code, _apiMessage(e));
    }
    final job = latest != null && latest!.isDone
        ? latest!
        : await done.future.timeout(
            settle,
            onTimeout: () => latest ?? const OutfitJob(status: 'unknown'),
          );
    if (job.succeeded) return (jobId: id, job: job);
    throw OutfitJobException(
      job.errorCode ?? 'internal',
      job.errorMessage ?? '処理に失敗しました。もう一度お試しください',
    );
  } finally {
    await sub.cancel();
  }
}

String _apiMessage(ApiException e) => switch (e.statusCode) {
  403 => '写真の登録は Google でログインした時だけ使えます',
  429 => '今日の回数の上限に達しました',
  400 => '写真を読み取れませんでした。撮りなおしてください',
  _ => '処理に失敗しました。通信を確かめて、もう一度お試しください',
};
