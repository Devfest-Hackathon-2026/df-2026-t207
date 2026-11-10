import 'package:flutter/widgets.dart';

import '../api/api_client.dart';
import '../api/social_models.dart';
import 'friend_outfit_items.dart';

class SocialFriend {
  const SocialFriend({
    required this.id,
    required this.name,
    this.postCount,
    this.streakDays,
    this.todayOutfit,
    this.todayItems = const [],
    this.isGeneratedOutfit = false,
    this.profileImage,
    this.profileCrop,
    this.postDate,
    this.liked = false,
  });

  final String id;
  final String name;
  final int? postCount;
  final int? streakDays;
  final ImageProvider? todayOutfit;
  final List<FriendOutfitItem> todayItems;
  final bool isGeneratedOutfit;
  final ImageProvider? profileImage;
  final String? profileCrop;
  final String? postDate;
  final bool liked;

  SocialFriend withLike(bool liked) => SocialFriend(
    id: id,
    name: name,
    postCount: postCount,
    streakDays: streakDays,
    todayOutfit: todayOutfit,
    todayItems: todayItems,
    isGeneratedOutfit: isGeneratedOutfit,
    profileImage: profileImage,
    profileCrop: profileCrop,
    postDate: postDate,
    liked: liked,
  );
}

class SocialNotice {
  const SocialNotice({
    required this.title,
    this.id,
    this.type = 'friend_accepted',
    this.requestId,
    this.jobId,
  });

  final String title;
  final String? id;
  final String type;
  final String? requestId;
  final String? jobId;
}

/// アプリ内で表示するフレンドと通知。
class SocialActivity extends ChangeNotifier {
  SocialActivity({this.api});

  final _friends = <SocialFriend>[];
  final _requests = <SocialFriend>[];
  final _notices = <SocialNotice>[];
  final _unread = <SocialNotice>{};
  final ApiClient? api;
  final _savedItems = <(String, String, int), String>{};
  List<FriendRequest> outgoing = const [];
  String? friendCode;
  int _unreadCount = 0;
  int _friendsRefresh = 0;
  int _noticesRefresh = 0;
  bool _disposed = false;
  bool _enabled = false;
  bool friendsUnavailable = false;
  bool noticesUnavailable = false;
  bool get connected => _enabled && api != null;

  List<SocialFriend> get friends => List.unmodifiable(_friends);
  List<SocialFriend> get requests => List.unmodifiable(_requests);
  List<SocialNotice> get notices => List.unmodifiable(_notices);
  bool get hasUnread => _unreadCount > 0 || _unread.isNotEmpty;

  bool isUnread(SocialNotice notice) => _unread.contains(notice);

  void updateAccount({required bool anonymous, String? code, int unread = 0}) {
    _enabled = !anonymous;
    friendCode = code;
    if (connected && _noticesRefresh == 0) _unreadCount = unread;
  }

  Future<void> refreshFriends() async {
    if (!connected) return;
    final refresh = ++_friendsRefresh;
    final client = api!;
    final List<FriendRecord> friends;
    final FriendRequests requests;
    try {
      (friends, requests) = await (
        client.getFriends(),
        client.getFriendRequests(),
      ).wait;
    } catch (_) {
      if (!_disposed && refresh == _friendsRefresh) {
        friendsUnavailable = true;
        notifyListeners();
      }
      return;
    }
    if (_disposed || refresh != _friendsRefresh) return;
    friendsUnavailable = false;
    _friends
      ..clear()
      ..addAll(friends.map(_friendFromRecord));
    _requests
      ..clear()
      ..addAll(
        requests.incoming.map(
          (item) => SocialFriend(id: item.id, name: item.name),
        ),
      );
    outgoing = requests.outgoing;
    notifyListeners();
  }

  SocialFriend _friendFromRecord(FriendRecord record) {
    final client = api!;
    final post = record.today;
    return SocialFriend(
      id: record.id,
      name: record.name,
      profileImage: record.profileImage == null
          ? null
          : client.image(record.profileImage!, version: record),
      profileCrop: record.profileCrop,
      todayOutfit: post == null
          ? null
          : client.image(post.image, version: post),
      postDate: post?.date,
      liked: post?.liked ?? false,
      todayItems: [
        if (post != null) ...[
          for (final (index, item) in post.items.indexed)
            FriendOutfitItem(
              index: index,
              slot: item.slot,
              label: item.label,
              color: item.color,
              memo: item.memo,
              image: client.image(item.image, version: post),
            ),
          for (final note in post.notes)
            FriendOutfitItem(slot: '', label: 'その他', memo: note),
        ],
      ],
    );
  }

  Future<void> refreshNotices() async {
    if (!connected) return;
    final refresh = ++_noticesRefresh;
    final Notifications result;
    try {
      result = await api!.getNotifications();
    } catch (_) {
      if (!_disposed && refresh == _noticesRefresh) {
        noticesUnavailable = true;
        notifyListeners();
      }
      return;
    }
    if (_disposed || refresh != _noticesRefresh) return;
    noticesUnavailable = false;
    _notices.clear();
    _unread.clear();
    _unreadCount = result.unread;
    for (final item in result.items) {
      final notice = SocialNotice(
        title: item.text,
        id: item.id,
        type: item.type,
        requestId: item.requestId,
        jobId: item.jobId,
      );
      _notices.add(notice);
      if (!item.read) _unread.add(notice);
    }
    notifyListeners();
  }

  Future<void> markRead(SocialNotice notice) async {
    if (!_unread.contains(notice)) return;
    if (connected) {
      await api!.readNotifications([notice.id!]);
      if (_disposed) return;
      final unread = _unread.where((item) => item.id == notice.id).firstOrNull;
      if (_unread.remove(unread)) {
        if (_unreadCount > 0) _unreadCount--;
        notifyListeners();
      }
      await refreshNotices();
    } else if (_unread.remove(notice)) {
      notifyListeners();
    }
  }

  Future<void> markAllRead() async {
    if (!hasUnread) return;
    if (connected) {
      await api!.readNotifications();
      if (_disposed) return;
      _unread.clear();
      _unreadCount = 0;
      notifyListeners();
      await refreshNotices();
    } else {
      _unread.clear();
      notifyListeners();
    }
  }

  Future<bool> sendRequest(String code) async {
    final request = await api!.requestFriend(code);
    await refreshFriends();
    return request.accepted;
  }

  Future<void> cancelRequest(String id) async {
    await api!.cancelFriendRequest(id);
    await refreshFriends();
  }

  Future<void> respondToRequest(
    SocialFriend friend, {
    required bool accept,
  }) async {
    if (connected) {
      await api!.respondToFriendRequest(friend.id, accept: accept);
      if (_disposed) return;
      _requests.removeWhere((item) => item.id == friend.id);
      notifyListeners();
      await Future.wait([refreshFriends(), refreshNotices()]);
      return;
    }
    if (!_requests.remove(friend)) return;
    if (accept) _friends.add(friend);
    _unread.removeWhere((notice) => notice.requestId == friend.id);
    notifyListeners();
  }

  Future<void> removeFriend(SocialFriend friend) async {
    if (connected) {
      await api!.removeFriend(friend.id);
      if (_disposed) return;
      _friendsRefresh++;
      _friends.removeWhere((item) => item.id == friend.id);
      notifyListeners();
      return;
    }
    if (_friends.remove(friend)) notifyListeners();
  }

  Future<void> setLike(SocialFriend friend, bool liked) async {
    await api!.setFriendLike(friend.id, liked);
    if (_disposed) return;
    _friendsRefresh++;
    final index = _friends.indexWhere(
      (item) => item.id == friend.id && item.postDate == friend.postDate,
    );
    if (index < 0) return;
    _friends[index] = _friends[index].withLike(liked);
    notifyListeners();
  }

  Future<void> toggleSave(SocialFriend friend, int index) async {
    final key = (friend.id, friend.postDate!, index);
    final id = _savedItems[key];
    if (id == null) {
      final saved = await api!.saveFriendItem(friend.id, index);
      if (!_disposed) _savedItems[key] = saved.id;
    } else {
      await deleteSave(id);
    }
    if (!_disposed) notifyListeners();
  }

  bool isSaved(SocialFriend friend, int index) =>
      _savedItems.containsKey((friend.id, friend.postDate, index));

  Future<void> deleteSave(String id) async {
    final client = api!;
    try {
      await client.deleteSave(id);
    } catch (_) {
      // 応答を受け取れなかった場合も、一覧で解除済みか確かめる。
      final remaining = await client.getSaves();
      if (remaining.any((item) => item.id == id)) rethrow;
    }
    _savedItems.removeWhere((_, saved) => saved == id);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
