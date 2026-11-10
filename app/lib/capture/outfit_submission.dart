import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../api/api_models.dart';
import '../register/outfit_job.dart';

/// 撮影画面を閉じても、アプリ内で本人の処理状況を受け取る。
class OutfitSubmission extends ChangeNotifier {
  OutfitSubmission(this.api, {OutfitJobSource? jobs})
    : _jobs = jobs ?? FirestoreOutfitJobSource() {
    if (!_android) return;
    _notifications.setMethodCallHandler((call) async {
      if (call.method == 'openRequested') await _readNotificationTap();
    });
    unawaited(_readNotificationTap());
  }

  final ApiClient api;
  final OutfitJobSource _jobs;
  static const _notifications = MethodChannel(
    'jp.dfhack26.app/outfit_notifications',
  );
  static bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  StreamSubscription<OutfitJob?>? _subscription;
  Future<void>? _permissionRequest;
  String? _uid;
  String? _jobId;
  String? _openedJob;
  String? _foregroundCompletion;
  bool _disposed = false;
  int _generation = 0;
  OutfitJob? result;
  String? error;
  bool remoteNotificationsEnabled = false;

  String? get jobId => _jobId;
  bool get processing => _jobId != null && result == null && error == null;

  Future<OutfitJob?> readReadyJob(String uid, String jobId) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(jobId)) return null;
    final user = FirebaseFirestore.instance.doc('users/$uid');
    final (posted, job) = await (
      user
          .collection('dailyOutfits')
          .where('jobId', isEqualTo: jobId)
          .limit(1)
          .get(const GetOptions(source: Source.server)),
      user
          .collection('jobs')
          .doc(jobId)
          .get(const GetOptions(source: Source.server)),
    ).wait;
    final data = job.data();
    if (posted.docs.isNotEmpty || data == null) return null;
    final result = OutfitJob.fromJson(data);
    return result.succeeded ? result : null;
  }

  Future<T?> _native<T>(String method, [Map<String, String>? arguments]) async {
    if (!_android) return null;
    try {
      return await _notifications.invokeMethod<T>(method, arguments);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> _readNotificationTap() async {
    final job = await _native<String>('takeOpenJob');
    if (_disposed || job == null) return;
    _openedJob = job;
    notifyListeners();
  }

  bool takeResultOpening() {
    if (_openedJob == null || _openedJob != _jobId || result == null) {
      return false;
    }
    _openedJob = null;
    return true;
  }

  String? takeForegroundCompletion() {
    final job = _foregroundCompletion;
    _foregroundCompletion = null;
    return job;
  }

  Future<void> start(String uid, Uint8List jpeg) async {
    if (processing || result != null) {
      throw ApiException(409, 'pending_outfit', '先に通知から処理中のコーデを確認してください');
    }
    final id = newJobId();
    _begin(uid, id);
    await _native<void>('remember', {'uid': uid, 'job': id});
    if (_jobId != id) return;
    _permissionRequest = _native<void>('permission');
    unawaited(_send(uid, id, jpeg));
  }

  Future<void> restore(String uid) async {
    if (!_android || _jobId != null) return;
    final generation = _generation;
    final id = await _native<String>('pendingJob', {'uid': uid});
    if (id == null || generation != _generation) return;
    try {
      final db = FirebaseFirestore.instance;
      // 登録直後にアプリが終了しても、同じ結果を再登録させない。
      final posted = await db
          .collection('users/$uid/dailyOutfits')
          .where('image', isEqualTo: 'users/$uid/jobs/$id/outfit.png')
          .limit(1)
          .get(const GetOptions(source: Source.server));
      if (generation != _generation) return;
      if (posted.docs.isNotEmpty) {
        await _native<void>('forget', {'uid': uid, 'job': id});
        return;
      }
      final ref = db.doc('users/$uid/jobs/$id');
      _begin(uid, id);
      var sawProcessing = false;
      _subscription = ref
          .snapshots(includeMetadataChanges: true)
          .map((snapshot) {
            final data = snapshot.data();
            if (data != null) return OutfitJob.fromJson(data);
            if (snapshot.metadata.isFromCache) return null;
            return const OutfitJob(
              status: 'failed',
              errorMessage: '処理の記録が見つかりません。もう一度撮影してください',
            );
          })
          .listen((job) {
            if (job == null) return;
            if (!job.isDone) sawProcessing = true;
            _update(id, job, announceInApp: sawProcessing);
          }, onError: (Object _) => _fail(id, '処理状況を確認できませんでした'));
    } catch (_) {
      // 通信が戻ったら、ホームの更新時に再取得する。
    }
  }

  void _begin(String uid, String id) {
    _generation++;
    _subscription?.cancel();
    _uid = uid;
    _jobId = id;
    if (_openedJob != id) _openedJob = null;
    _foregroundCompletion = null;
    _permissionRequest = null;
    result = null;
    error = null;
    _subscription = null;
    notifyListeners();
  }

  Future<void> _send(String uid, String id, Uint8List jpeg) async {
    try {
      final done = await runOutfitJob(
        api: api,
        jobs: _jobs,
        uid: uid,
        photo: jpeg,
        jobId: id,
        onProgress: (job) => _update(id, job, announceInApp: true),
      );
      _update(id, done.job, announceInApp: true);
    } on OutfitJobException catch (exception) {
      _fail(id, exception.message);
    } catch (_) {
      _fail(id, '処理状況を確認できませんでした。通信を確認してください');
    }
  }

  void _update(String id, OutfitJob job, {required bool announceInApp}) {
    if (_jobId != id || result != null) return;
    if (job.failed) {
      _fail(id, job.errorMessage ?? '写真を処理できませんでした');
      return;
    }
    if (job.succeeded) {
      if (job.outfitImage == null) {
        _fail(id, '処理結果を取得できませんでした');
        return;
      }
      result = job;
      error = null;
      _subscription?.cancel();
      if (announceInApp &&
          SchedulerBinding.instance.lifecycleState ==
              AppLifecycleState.resumed) {
        _foregroundCompletion = id;
      } else {
        unawaited(_notifyCompletion(id));
      }
    }
    notifyListeners();
  }

  Future<void> _notifyCompletion(String id) async {
    if (remoteNotificationsEnabled) return;
    await _permissionRequest;
    final uid = _uid;
    if (uid == null || _jobId != id) return;
    await _native<void>('complete', {'uid': uid, 'job': id});
  }

  void _fail(String id, String message) {
    if (_jobId != id || result != null || error != null) return;
    error = message;
    notifyListeners();
  }

  void clear({bool forget = true}) {
    final uid = _uid;
    final id = _jobId;
    if (uid != null && id != null) {
      unawaited(
        _native<void>(forget ? 'forget' : 'cancel', {'uid': uid, 'job': id}),
      );
      if (_openedJob == id) _openedJob = null;
    }
    _generation++;
    _uid = null;
    _jobId = null;
    _foregroundCompletion = null;
    _permissionRequest = null;
    result = null;
    error = null;
    _subscription?.cancel();
    _subscription = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _jobId = null;
    _subscription?.cancel();
    if (_android) _notifications.setMethodCallHandler(null);
    super.dispose();
  }
}
