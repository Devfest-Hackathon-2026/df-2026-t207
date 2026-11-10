import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import 'demo_mode.dart';
import '../api/api_models.dart';
import '../ble/ble_controller.dart';
import '../capture/outfit_camera_screen.dart';
import '../capture/outfit_items_review_screen.dart';
import '../capture/outfit_submission.dart';
import '../capture/processed_outfit_screen.dart';
import '../common/outfit_item_tile.dart';
import '../home/home_screen.dart';
import '../mypage/my_page_screen.dart';
import '../mypage/outfit_history.dart';
import '../mypage/profile_photo.dart';
import '../services/auth_service.dart';
import '../settings/settings_screen.dart';
import '../settings/settings_store.dart';
import '../shell/app_shell.dart';
import '../shell/floating_nav_bar.dart';
import '../social/device_notifications.dart';
import '../social/friend_profile_screen.dart';
import '../social/friend_item_match.dart';
import '../social/friends_screen.dart';
import '../social/notifications_screen.dart';
import '../social/saved_items_screen.dart';
import '../social/social_activity.dart';
import '../viewer/nearby_outfits_screen.dart';
import '../viewer/outfit_match_screen.dart';
import 'app_banner.dart';
import 'app_loading.dart';
import 'closet_page.dart';
import 'confirmation_sheet.dart';
import 'publishing_controller.dart';
import 'android_app_pitch.dart';
import 'open_url.dart';
import 'web_stage.dart';

/// ログインの後の本体。api から自分の状態を読み、ホームとマイページに渡す。
/// 公開の切り替えは [PublishingController] が BLE の常駐と一緒に行う。
class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    required this.auth,
    required this.api,
    required this.ble,
    required this.submission,
    required this.onDarkModeChanged,
    this.historySource,
  });

  final AuthService auth;
  final ApiClient api;
  final BleController ble;
  final OutfitSubmission submission;
  final Future<void> Function(bool) onDarkModeChanged;

  /// コーデカレンダーの記録を読む口。省略すると Firestore
  final OutfitHistorySource? historySource;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  late final _social = SocialActivity(api: widget.api);
  final _shellKey = GlobalKey<AppShellState>();
  DeviceNotifications? _deviceNotifications;
  Me? _me;
  ProfilePhoto? _profilePhoto;
  Future<ProfilePhoto?>? _profilePhotoLoad;
  Future<void>? _profilePhotoWrite;
  TodayOutfit? _today;
  Map<String, WardrobeItem> _wardrobe = const {};
  int? _postCount;
  int? _streakDays;
  Map<DateTime, CalendarOutfit> _outfitHistory = const {};
  int _historyRequest = 0;
  late final _history = OutfitHistory(
    widget.historySource ?? FirestoreOutfitHistorySource(),
  );

  /// カレンダーで見ている月 (その月の 1 日)。記録はこの月の分だけ読む
  DateTime _calendarMonth = DateTime(DateTime.now().year, DateTime.now().month);
  final _loadedMonths = <DateTime>{};
  int _loadRequest = 0;
  bool _loading = true;
  bool _nearbyOpen = false;
  bool _outfitReviewOpen = false;
  VoidCallback? _dismissResultBanner;

  late final PublishingController _publishing = PublishingController(
    api: widget.api,
    ble: widget.ble,
  );
  late final Future<void> _publishingReady = _publishing.init();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _publishing.addListener(_onPublishingChanged);
    widget.submission.addListener(_onSubmissionChanged);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deviceNotifications?.dispose();
    widget.submission.remoteNotificationsEnabled = false;
    _hideResultBanner();
    _publishing.removeListener(_onPublishingChanged);
    widget.submission.removeListener(_onSubmissionChanged);
    _publishing.dispose();
    _social.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refreshSocial());
  }

  Future<void> _refreshSocial() async {
    await Future.wait([
      _social.refreshFriends().catchError((Object _) {}),
      _social.refreshNotices().catchError((Object _) {}),
    ]);
  }

  void _startDeviceNotifications(Me me) {
    if (me.isAnonymous ||
        _deviceNotifications != null ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        Firebase.apps.isEmpty) {
      return;
    }
    final device = DeviceNotifications(
      api: widget.api,
      onRefresh: () => unawaited(_refreshSocial()),
      onOpen: (data) {
        if (!mounted || _me?.uid != me.uid) return;
        unawaited(_refreshSocial());
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openPush(data);
        });
        WidgetsBinding.instance.ensureVisualUpdate();
      },
      onRegistered: (enabled) {
        widget.submission.remoteNotificationsEnabled = enabled;
      },
    );
    _deviceNotifications = device;
    unawaited(device.start());
  }

  void _openPush(Map<String, dynamic> data) {
    switch (data['type']) {
      case 'outfit_ready':
        if (data['jobId'] case final String jobId) {
          unawaited(_openNoticeResult(jobId));
        } else {
          _openNotifications();
        }
      case 'friend_request' || 'friend_accepted':
        _openTab(AppTab.community);
      case 'like':
        _openTab(AppTab.home);
      default:
        _openNotifications();
    }
  }

  void _openTab(AppTab tab) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    _shellKey.currentState?.selectTab(tab);
  }

  void _onPublishingChanged() {
    if (mounted) setState(() {});
  }

  void _onSubmissionChanged() {
    if (!mounted) return;
    setState(() {});
    final submission = widget.submission;
    if (submission.result != null) {
      unawaited(_social.refreshNotices().catchError((Object _) {}));
    }
    if (submission.result == null) _hideResultBanner();
    if (_me == null) return;
    final openFromNotification = submission.takeResultOpening();
    final completedJob = submission.takeForegroundCompletion();
    if (!openFromNotification && completedJob == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (openFromNotification) {
        _openSubmission(context);
      } else if (completedJob == submission.jobId && !_outfitReviewOpen) {
        _dismissResultBanner = showAppBanner(
          context,
          'コーデの処理が完了しました',
          icon: Icons.check_circle_outline,
          actionLabel: '結果を見る',
          onAction: () => _openSubmission(context),
        );
      }
    });
  }

  void _hideResultBanner() {
    _dismissResultBanner?.call();
    _dismissResultBanner = null;
  }

  Future<void> _load() async {
    final request = ++_loadRequest;
    final previousMe = _me;
    if (previousMe == null) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        widget.api.getMe(),
        widget.api.getTodayOutfit(),
        widget.api.getWardrobe(),
      ]);
      final me = results[0] as Me;
      if (!mounted || request != _loadRequest) return;
      final newAccount = _me?.uid != me.uid;
      final applyMe = newAccount || identical(_me, previousMe);
      final restorePhoto =
          newAccount ||
          previousMe?.profileImage != me.profileImage ||
          previousMe?.profileCrop != me.profileCrop;
      if (applyMe && restorePhoto) {
        _restoreProfilePhoto(me);
      }
      _social.updateAccount(
        anonymous: me.isAnonymous,
        code: me.friendCode,
        unread: me.unreadNotifications,
      );
      setState(() {
        // 更新中に設定や公開状態を変更した場合は、その変更を残す。
        if (applyMe) _me = me;
        _today = results[1] as TodayOutfit?;
        _wardrobe = {
          for (final item in results[2] as List<WardrobeItem>)
            item.itemId: item,
        };
        _loading = false;
        if (newAccount) {
          _postCount = null;
          _streakDays = null;
          _outfitHistory = const {};
        }
      });
      if (applyMe && !restorePhoto) _syncLocalProfilePhoto(me);
      if (!me.isAnonymous && _historyReady) {
        _loadHistory(me.uid);
        widget.submission.restore(me.uid);
      }
      _startDeviceNotifications(me);
      final socialRefresh = _refreshSocial();
      _onSubmissionChanged();
      // サーバでは公開中なのに常駐が止まっていたら (入れ直した後など) 始め直す
      await _publishingReady;
      if (!mounted || request != _loadRequest) return;
      final resumed = await _publishing.resumeIfNeeded(_me!);
      if (resumed != null && request == _loadRequest) {
        _applyPublishState(resumed);
      }
      await socialRefresh;
    } catch (_) {
      if (!mounted || request != _loadRequest) return;
      if (_me == null) {
        setState(() => _loading = false);
      } else {
        showAppBanner(context, 'ホームを更新できませんでした', icon: Icons.error_outline);
      }
    }
  }

  /// 投稿数・連続記録と、見ている月のカレンダーを読み直す (M14: 月ごとに日付で絞って読む)
  Future<void> _loadHistory(String uid) async {
    final request = ++_historyRequest;
    _loadedMonths.clear();
    unawaited(_loadMonth(uid, _calendarMonth));
    try {
      final (count, streak) = await (
        _history.postCount(uid),
        _history.streak(uid),
      ).wait;
      if (!mounted || _me?.uid != uid || request != _historyRequest) return;
      setState(() {
        _postCount = count;
        _streakDays = streak;
      });
    } catch (_) {
      // 履歴を取得できなくても、今日のコーデと公開状態は使える。
    }
  }

  Future<void> _loadMonth(String uid, DateTime month) async {
    if (!_loadedMonths.add(month)) return;
    final request = _historyRequest;
    try {
      final outfits = await _history.month(uid, month.year, month.month);
      if (!mounted || _me?.uid != uid || request != _historyRequest) return;
      setState(() {
        _outfitHistory = {
          for (final entry in _outfitHistory.entries)
            if (entry.key.year != month.year || entry.key.month != month.month)
              entry.key: entry.value,
          ...outfits,
        };
      });
    } catch (_) {
      _loadedMonths.remove(month); // 次に開いた時に読み直す
    }
  }

  void _onCalendarMonthChanged(DateTime month) {
    _calendarMonth = month;
    final uid = _me?.uid;
    if (uid != null && !_me!.isAnonymous && _historyReady) {
      _loadMonth(uid, month);
    }
  }

  bool get _historyReady =>
      widget.historySource != null || Firebase.apps.isNotEmpty;

  DateTime? get _todayDate {
    final today = _today;
    return today == null ? null : DateTime.tryParse('${today.date}T00:00:00Z');
  }

  ImageProvider _todayImage(TodayOutfit outfit) =>
      widget.api.image(outfit.image, version: (outfit.date, outfit.jobId));

  void _openCalendarDay(BuildContext context, DateTime date) {
    if (ModalRoute.of(context)?.isCurrent != true) return;
    final history = _outfitHistory[date];
    final today = date == _todayDate ? _today : null;
    if (history == null && today == null) return;
    final image = history == null
        ? _todayImage(today!)
        : widget.api.image(history.image);
    final items = history == null
        ? today!.items
        : history.snapshot ??
              [for (final id in history.itemIds) ?_wardrobe[id]];
    Navigator.of(context).push<void>(
      outfitReviewPhotoRoute(
        (_) => OutfitItemsReviewScreen.view(
          title: '${date.year}年${date.month}月${date.day}日のコーデ',
          outfitImage: image,
          items: [
            for (final (index, item) in items.indexed)
              OutfitReviewItem(
                index: index,
                label: slotLabel(item.slot),
                searchLabel: item.label,
                slot: item.slot,
                image: widget.api.image(item.image),
                color: item.color,
                memo: history?.snapshot == null
                    ? history?.memos[item.itemId] ?? item.memo ?? ''
                    : item.memo ?? '',
                pattern: item.pattern,
                materialGuess: item.materialGuess,
              ),
            for (final (index, note)
                in (history?.notes ?? today?.itemNotes ?? const <String>[])
                    .indexed)
              OutfitReviewItem(
                index: items.length + index,
                label: 'その他',
                memo: note,
              ),
          ],
        ),
      ),
    );
  }

  void _restoreProfilePhoto(Me me) {
    final path = me.profileImage;
    final photoLoad =
        (path == null
                ? loadProfilePhoto(me.uid)
                : widget.api
                      .imageBytes(path)
                      .then(
                        (bytes) =>
                            ProfilePhoto.fromRemote(bytes, me.profileCrop),
                      ))
            .catchError((Object _) => null);
    if (_me?.uid != me.uid) _profilePhoto = null;
    _profilePhotoLoad = photoLoad;
    photoLoad.then((photo) {
      if (mounted && identical(_profilePhotoLoad, photoLoad)) {
        setState(() {
          _profilePhoto = photo;
          _profilePhotoLoad = null;
        });
        _syncLocalProfilePhoto(me);
      }
    });
  }

  void _syncLocalProfilePhoto(Me me) {
    final photo = _profilePhoto;
    if (photo == null ||
        me.isAnonymous ||
        me.profileImage != null ||
        _me?.profileImage != null ||
        _profilePhotoLoad != null ||
        _profilePhotoWrite != null) {
      return;
    }
    // 失敗しても端末内に残し、次にアカウント情報を更新した時に再試行する。
    unawaited(_saveProfilePhoto(me, photo).catchError((Object _) {}));
  }

  Future<void> _saveProfilePhoto(Me me, ProfilePhoto? photo) async {
    final pending = _profilePhotoWrite;
    final write = pending == null
        ? _writeProfilePhoto(me, photo)
        : pending
              .catchError((Object _) {})
              .then((_) => _writeProfilePhoto(me, photo));
    _profilePhotoWrite = write;
    try {
      await write;
    } finally {
      if (identical(_profilePhotoWrite, write)) _profilePhotoWrite = null;
    }
  }

  Future<void> _writeProfilePhoto(Me me, ProfilePhoto? photo) async {
    if (!mounted || _me?.uid != me.uid || !widget.auth.isSignedIn) return;
    final crop = photo?.encodeCrop();
    if (me.isAnonymous) {
      await saveProfilePhoto(me.uid, photo);
    } else {
      if (photo == null) {
        await widget.api.deleteProfileImage();
      } else {
        await widget.api.putProfileImage(photo.bytes, crop!);
      }
      await saveProfilePhoto(me.uid, null).catchError((Object _) {});
    }
    if (!mounted || _me?.uid != me.uid) return;
    setState(() {
      _profilePhoto = photo;
      _profilePhotoLoad = null;
      if (!me.isAnonymous) {
        _me = _me!.withProfileImage(
          photo == null ? null : '/v1/me/profile-image',
          crop,
        );
      }
    });
  }

  Future<void> _setPublishing(bool publish) async {
    // Web デモ (匿名) は、今日のコーデを公開しているデモの見る人として動く。サーバも切り替えを受けない
    if (_me?.isAnonymous == true) {
      if (mounted) showAppBanner(context, 'デモでは公開中のままです');
      return;
    }
    await _publishingReady;
    final state = await _publishing.setPublishing(publish);
    _applyPublishState(state);
  }

  void _applyPublishState(PublishState state) {
    if (!mounted || _me == null) return;
    final me = _me!;
    setState(() {
      _me = me.withPublishing(state);
    });
  }

  void _openCloset(ValueChanged<AppTab> goTo) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ClosetPage(
          api: widget.api,
          onAddPressed: () => goTo(AppTab.post),
          onItemDeleted: (id) => setState(() {
            _wardrobe = {..._wardrobe}..remove(id);
            if (_today case final today?) {
              _today = TodayOutfit(
                date: today.date,
                image: today.image,
                jobId: today.jobId,
                itemNotes: today.itemNotes,
                items: today.items.where((item) => item.itemId != id).toList(),
              );
            }
          }),
        ),
      ),
    );
  }

  void _openNotifications([ValueChanged<AppTab>? goTo]) {
    unawaited(_social.refreshNotices().catchError((Object _) {}));
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => NotificationsScreen(
          activity: _social,
          submission: widget.submission,
          onOpenOutfit: () => _openSubmission(context),
          onDiscardOutfit: () => _discardSubmission(context),
          onOpenFriends: () => _openTab(AppTab.community),
          onOpenNotice: (notice) {
            if (notice.type == 'outfit_ready' && notice.jobId != null) {
              _openNoticeResult(notice.jobId!);
              return;
            }
            final target = switch (notice.type) {
              'friend_request' || 'friend_accepted' => AppTab.community,
              'like' => AppTab.home,
              _ => null,
            };
            if (target == null) return;
            if (goTo == null) {
              _openTab(target);
            } else {
              Navigator.pop(context);
              goTo(target);
            }
          },
        ),
      ),
    );
  }

  Future<void> _openNoticeResult(String jobId) async {
    if (widget.submission.jobId == jobId) {
      await _openSubmission(context);
      return;
    }
    final me = _me;
    if (me == null || _outfitReviewOpen || !_historyReady) return;
    if (_today?.jobId == jobId) {
      _openTab(AppTab.home);
      return;
    }
    _outfitReviewOpen = true;
    try {
      final result = await widget.submission.readReadyJob(me.uid, jobId);
      if (!mounted || _me?.uid != me.uid) return;
      if (result == null) {
        showAppBanner(context, 'この処理結果は確認済みか、表示できません');
        return;
      }
      final outfit = await Navigator.of(context).push<TodayOutfit>(
        MaterialPageRoute(
          builder: (_) => ProcessedOutfitScreen(
            api: widget.api,
            jobId: jobId,
            outfit: result,
          ),
        ),
      );
      if (!mounted || outfit == null) return;
      setState(() => _today = outfit);
      showAppBanner(context, '今日のコーデを投稿しました', icon: Icons.check_circle_outline);
      await _load();
    } catch (_) {
      if (mounted) {
        showAppBanner(context, '処理結果を取得できませんでした', icon: Icons.error_outline);
      }
    } finally {
      _outfitReviewOpen = false;
    }
  }

  Future<void> _openCapture(BuildContext context) async {
    var submitted = false;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => OutfitCameraScreen(
          onPhotoConfirmed: (photo) async {
            final me = _me;
            if (me == null || me.isAnonymous) {
              throw ApiException(403, 'forbidden', 'コーデの投稿には Google ログインが必要です');
            }
            final bytes = await photo.readAsBytes();
            if (!mounted || _me?.uid != me.uid) return;
            await widget.submission.start(me.uid, bytes);
            submitted = true;
          },
        ),
      ),
    );
    if (mounted && submitted) _openTab(AppTab.home);
  }

  Future<void> _openSubmission(BuildContext context) async {
    _hideResultBanner();
    if (_outfitReviewOpen) return;
    final submission = widget.submission;
    final jobId = submission.jobId;
    final result = submission.result;
    if (result == null || jobId == null) {
      if (submission.error != null) _openCapture(context);
      return;
    }
    _outfitReviewOpen = true;
    TodayOutfit? outfit;
    try {
      outfit = await Navigator.of(context).push<TodayOutfit>(
        MaterialPageRoute(
          builder: (_) => ProcessedOutfitScreen(
            api: widget.api,
            jobId: jobId,
            outfit: result,
          ),
        ),
      );
    } finally {
      _outfitReviewOpen = false;
    }
    if (!mounted || outfit == null || submission.jobId != jobId) return;
    setState(() => _today = outfit);
    submission.clear();
    showAppBanner(
      this.context,
      '今日のコーデを投稿しました',
      icon: Icons.check_circle_outline,
    );
    await _load();
  }

  Future<void> _discardSubmission(BuildContext context) async {
    final jobId = widget.submission.jobId;
    final confirmed = await showConfirmationSheet(
      context,
      title: '処理結果を破棄しますか？',
      icon: Icons.delete_outline,
      confirmLabel: '破棄',
    );
    if (mounted && confirmed == true && widget.submission.jobId == jobId) {
      widget.submission.clear();
    }
  }

  Future<void> _editToday(
    BuildContext context,
    int? index,
    Object? heroTag,
  ) async {
    final original = _today;
    final jobId = original?.jobId;
    if (original == null || jobId == null) return;
    final updated = await Navigator.of(context).push<TodayOutfit>(
      outfitReviewPhotoRoute<TodayOutfit>(
        (_) => ProcessedOutfitScreen.edit(
          api: widget.api,
          jobId: jobId,
          outfit: original,
          heroTag: heroTag,
          initialItemIndex: index,
        ),
        heroTag: heroTag,
      ),
    );
    if (!mounted || updated == null || _today?.jobId != jobId) return;
    setState(() => _today = updated);
    await _load();
  }

  Future<void> _openNearby(BuildContext shellContext) async {
    if (_nearbyOpen) return;
    _nearbyOpen = true;
    const channel = MethodChannel('jp.dfhack26.app/viewer_security');
    final secure = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final mockNearby = secure && demoMode.value;
    var closed = false;
    var protectionRequested = false;
    Future<void>? protection;
    try {
      if (!shellContext.mounted) return;
      final today = _today;
      final route = MaterialPageRoute<void>(
        builder: (nearbyContext) => NearbyOutfitsScreen(
          loadNearby: () async {
            final publishing = _me?.publishing;
            if (!kIsWeb &&
                (_today == null ||
                    publishing?.isPublishing != true ||
                    publishing?.until?.isAfter(DateTime.now()) == false)) {
              return const NearbyResult(cards: [], viewerPublishing: false);
            }
            final NearbyResult result;
            if (mockNearby) {
              result = await widget.api.demoNearby();
            } else {
              await _publishingReady;
              result = await _publishing.loadNearby(
                viewerPublishing: publishing?.isPublishing,
              );
            }
            if (!closed &&
                secure &&
                result.cards.any(
                  (card) => card.expiresAt.isAfter(DateTime.now()),
                )) {
              protectionRequested = true;
              try {
                await (protection ??= channel.invokeMethod<void>('enable'));
              } catch (_) {
                protection = null;
                rethrow;
              }
            }
            if (result.cards.isNotEmpty) {
              stageShow(
                result.cards.first,
                widget.api.image(result.cards.first.image),
              );
            }
            return result;
          },
          imageFor: widget.api.image,
          onBlock: widget.api.blockCard,
          onReport: widget.api.reportCard,
          onSetLike: (cardId, liked) async {
            await widget.api.setCardLike(cardId, liked);
            stageLike(cardId, liked);
          },
          onCardShown: (card) => stageShow(card, widget.api.image(card.image)),
          onSaveItem: (cardId, itemId) async =>
              (await widget.api.saveCardItem(cardId, itemId)).id,
          onDeleteSave: _social.deleteSave,
          onMatch: (card, item) => Navigator.of(nearbyContext).push<void>(
            MaterialPageRoute(
              builder: (_) =>
                  OutfitMatchScreen(api: widget.api, card: card, item: item),
            ),
          ),
          onCapturePressed: kIsWeb ? null : () => _openCapture(nearbyContext),
          outfitToPublish: today == null ? null : _todayImage(today),
          onPublishPressed:
              !kIsWeb && today != null && _me?.isAnonymous == false
              ? () => _setPublishing(true)
              : null,
          isSimulated: kIsWeb || mockNearby,
        ),
      );
      await Navigator.of(shellContext).push(route);
      await route.completed;
    } finally {
      closed = true;
      try {
        if (protectionRequested) {
          try {
            await protection;
          } catch (_) {
            // 閉じている途中で有効化に失敗しても、解除は試す。
          }
          await channel.invokeMethod<void>('disable');
        }
      } on PlatformException catch (_) {
        if (mounted) _showNearbyUnavailable();
      } on MissingPluginException catch (_) {
        if (mounted) _showNearbyUnavailable();
      } finally {
        _nearbyOpen = false;
      }
    }
  }

  void _showNearbyUnavailable() {
    showAppBanner(context, '近くのコーデを開けませんでした', icon: Icons.error_outline);
  }

  void _openSettings({bool focusName = false}) {
    final me = _me;
    if (me == null) return;
    final today = _today;
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          displayName: me.displayName,
          isPublishing: me.publishing.isPublishing,
          fallbackPhoto: today == null ? null : _todayImage(today),
          photo: _profilePhoto,
          photoLoad: _profilePhotoLoad,
          focusName: focusName,
          onDarkModeChanged: widget.onDarkModeChanged,
          // Android だけ切り替えられる (Web デモは常にデモ)
          demoMode: !kIsWeb && defaultTargetPlatform == TargetPlatform.android
              ? demoMode
              : null,
          onSaveName: (name) async {
            // Web デモの審査員は Demo のまま (サーバも名前の変更を受けない)
            if (_me?.isAnonymous == true) {
              // 失敗として返し、設定の画面に「変更しました」を出させない
              throw ApiException(403, 'forbidden', 'デモでは名前を変えられません');
            }
            final updated = await widget.api.updateDisplayName(name);
            if (mounted && _me?.uid == me.uid) setState(() => _me = updated);
          },
          onSavePhoto: (photo) => _saveProfilePhoto(me, photo),
          onLogout: () async {
            if (_me?.publishing.isPublishing == true &&
                _me?.isAnonymous != true) {
              await _setPublishing(false);
            }
            await _deviceNotifications?.unregister();
            await widget.auth.signOut();
          },
        ),
      ),
    );
  }

  HomeOutfitItem _homeItem(WardrobeItem item) => HomeOutfitItem(
    id: item.itemId,
    slot: item.slot,
    label: item.label,
    image: widget.api.image(item.image),
    memo: item.memo ?? '',
  );

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_loading) {
      body = const AppLoadingScreen();
    } else if (_me == null) {
      body = _LoadError(onRetry: _load);
    } else {
      body = _shell(_me!);
    }
    if (!kIsWeb) return body;
    // Web デモは、検出が模擬であることを常に出す (spec.md の S16)
    return Column(
      children: [
        const _DemoBanner(),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: body,
          ),
        ),
      ],
    );
  }

  Widget _shell(Me me) {
    final today = _today;
    final todayDate = _todayDate;
    final todayImage = today == null ? null : _todayImage(today);
    final profilePhoto = _profilePhoto;
    return AppShell(
      key: _shellKey,
      // Web デモ (匿名) は投稿できないので、自分の服で試す人を Android アプリへ案内する
      onPostPressed: me.isAnonymous ? showAndroidAppSheet : _openCapture,
      homeBuilder: (context, goTo) => AppRefreshIndicator(
        onRefresh: _load,
        child: ListenableBuilder(
          listenable: _social,
          builder: (context, _) => HomeScreen(
            hasTodayOutfit: today != null,
            todayOutfitImage: todayImage,
            isPublishing: me.publishing.isPublishing,
            viewCountToday: me.viewCountToday,
            items: [
              for (final item in today?.items ?? const <WardrobeItem>[])
                _homeItem(item),
              for (final note in today?.itemNotes ?? const <String>[])
                HomeOutfitItem(slot: '', label: 'その他', memo: note),
            ],
            onEditOutfit: !me.isAnonymous && today?.jobId != null
                ? _editToday
                : null,
            loadClosetItems: () async =>
                (await widget.api.getWardrobe()).map(_homeItem).toList(),
            // Web デモ (匿名) では投稿の代わりに、近くのコーデへ進める
            onCapturePressed: () =>
                goTo(me.isAnonymous ? AppTab.search : AppTab.post),
            onPublishPressed: () => goTo(AppTab.myPage),
            onNotificationsPressed: () => _openNotifications(goTo),
            hasUnreadNotifications:
                _social.hasUnread ||
                widget.submission.result != null ||
                widget.submission.error != null,
            friendPosts: [
              for (final friend in _social.friends)
                if (friend.todayOutfit case final image?)
                  HomeFriendPost(
                    key: ValueKey((friend.id, friend.postDate)),
                    displayName: friend.name,
                    timeLabel: '今日',
                    image: image,
                    isGenerated: friend.isGeneratedOutfit,
                    items: friend.todayItems,
                    profileImage: friend.profileImage,
                    profileCrop: friend.profileCrop,
                    onOpenProfile: () =>
                        _shellKey.currentState?.openCommunityPage(
                          FriendProfileScreen.route(friend, _social),
                        ),
                    liked: friend.liked,
                    onLike: _social.connected
                        ? (liked) => _social.setLike(friend, liked)
                        : null,
                    onToggleSave: _social.connected
                        ? (index) => _social.toggleSave(friend, index)
                        : null,
                    isSaved: _social.connected
                        ? (index) => _social.isSaved(friend, index)
                        : null,
                    onMatch: _social.connected
                        ? (context, item) => openFriendItemMatch(
                            context,
                            widget.api,
                            friend,
                            item,
                          )
                        : null,
                  ),
            ],
          ),
        ),
      ),
      myPageBuilder: (context, goTo) => ListenableBuilder(
        listenable: _social,
        builder: (context, _) => MyPageScreen(
          displayName: me.displayName,
          headerImage: todayImage,
          profilePhoto: profilePhoto,
          // Web デモ (匿名) は履歴を読めないので、Demo の記録 (今日のコーデ 1 件) から出す。「—」で読み込み失敗に見せない
          postCount: me.isAnonymous ? (today == null ? 0 : 1) : _postCount,
          streakDays: me.isAnonymous ? (today == null ? 0 : 1) : _streakDays,
          calendarImages: {
            if (todayDate != null && todayImage != null) todayDate: todayImage,
            for (final entry in _outfitHistory.entries)
              entry.key: widget.api.image(entry.value.image),
          },
          onCalendarDayPressed: (date) => _openCalendarDay(context, date),
          onCalendarMonthChanged: _onCalendarMonthChanged,
          isPublishing: me.publishing.isPublishing,
          notice: _publishing.notice,
          closetCount: _wardrobe.length,
          friendCount: me.isAnonymous
              ? 0
              : (_social.connected ? _social.friends.length : null),
          onPublishChanged: _setPublishing,
          onClosetPressed: () => _openCloset(goTo),
          onSavedPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => SavedItemsScreen(activity: _social),
            ),
          ),
          onEditName: () => _openSettings(focusName: true),
          onSettingsPressed: _openSettings,
        ),
      ),
      communityBuilder: (_, _) => FriendsScreen(activity: _social),
      onSearchPressed: _openNearby,
    );
  }
}

class _DemoBanner extends StatelessWidget {
  const _DemoBanner();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xff141414),
      child: SafeArea(
        bottom: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Flexible(
                child: Text(
                  'デモモード: 近くの人は AI 生成のサンプルです',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              // PC の広い画面では、外枠の左に QR を出すので帯には置かない
              // 外枠の中では MediaQuery がスマホの大きさになるので、窓そのものの幅で決める
              if (!showsStage(context)) ...[
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => openUrl(Uri.base.resolve(apkPath).toString()),
                  child: const Text(
                    'Android アプリ',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      decoration: TextDecoration.underline,
                      decorationColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '読み込めませんでした',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('もう一度')),
            ],
          ),
        ),
      ),
    );
  }
}
