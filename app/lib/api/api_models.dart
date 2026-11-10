/// docs/api.yaml の形をそのまま写したデータ。画面に要る所だけを持つ。
library;

class ApiException implements Exception {
  ApiException(this.statusCode, this.code, this.message);

  final int statusCode;

  /// `Error.error.code` (例 quota_exceeded)。形が違う応答の時は `http_<状態>`。
  final String code;
  final String message;

  @override
  String toString() => 'ApiException($statusCode, $code): $message';
}

class BroadcastId {
  const BroadcastId({required this.slotStart, required this.id});

  factory BroadcastId.fromJson(Map<String, dynamic> j) => BroadcastId(
    slotStart: DateTime.parse(j['slotStart'] as String),
    id: j['id'] as String,
  );

  final DateTime slotStart;
  final String id;
}

class PublishState {
  const PublishState({
    required this.visibility,
    this.until,
    this.broadcastIds = const [],
  });

  factory PublishState.fromJson(Map<String, dynamic> j) => PublishState(
    visibility: j['visibility'] as String,
    until: j['until'] == null ? null : DateTime.parse(j['until'] as String),
    broadcastIds: [
      for (final b in (j['broadcastIds'] as List? ?? const []))
        BroadcastId.fromJson(b as Map<String, dynamic>),
    ],
  );

  /// `nearby` か `private`。
  final String visibility;
  final DateTime? until;

  /// `nearby` にした時だけ入る、その日の残りの匿名 ID。
  final List<BroadcastId> broadcastIds;

  bool get isPublishing => visibility == 'nearby';
}

class Me {
  const Me({
    required this.uid,
    required this.displayName,
    required this.isAnonymous,
    required this.publishing,
    required this.viewCountToday,
    required this.hasPhoto,
    this.friendCode,
    this.profileImage,
    this.profileCrop,
    this.unreadNotifications = 0,
  });

  factory Me.fromJson(Map<String, dynamic> j) => Me(
    uid: j['uid'] as String,
    displayName: j['displayName'] as String? ?? '',
    isAnonymous: j['isAnonymous'] as bool? ?? false,
    publishing: PublishState.fromJson(j['publishing'] as Map<String, dynamic>),
    viewCountToday: j['viewCountToday'] as int? ?? 0,
    hasPhoto: j['hasPhoto'] as bool? ?? false,
    friendCode: j['friendCode'] as String?,
    profileImage: j['profileImage'] as String?,
    profileCrop: j['profileCrop'] as String?,
    unreadNotifications: j['unreadNotifications'] as int? ?? 0,
  );

  final String uid;
  final String displayName;
  final bool isAnonymous;
  final PublishState publishing;
  final int viewCountToday;
  final bool hasPhoto;
  final String? friendCode;
  final String? profileImage;
  final String? profileCrop;
  final int unreadNotifications;

  Me withPublishing(PublishState state) => Me(
    uid: uid,
    displayName: displayName,
    isAnonymous: isAnonymous,
    publishing: state,
    viewCountToday: viewCountToday,
    hasPhoto: hasPhoto,
    friendCode: friendCode,
    profileImage: profileImage,
    profileCrop: profileCrop,
    unreadNotifications: unreadNotifications,
  );

  Me withProfileImage(String? image, String? crop) => Me(
    uid: uid,
    displayName: displayName,
    isAnonymous: isAnonymous,
    publishing: publishing,
    viewCountToday: viewCountToday,
    hasPhoto: hasPhoto,
    friendCode: friendCode,
    profileImage: image,
    profileCrop: crop,
    unreadNotifications: unreadNotifications,
  );
}

/// 手持ちの服 1 着 (Garment + 手持ちの id など)。
class WardrobeItem {
  const WardrobeItem({
    required this.itemId,
    required this.slot,
    required this.label,
    required this.color,
    required this.image,
    this.category,
    this.layer,
    this.pattern,
    this.materialGuess,
    this.memo,
    this.createdAt,
  });

  factory WardrobeItem.fromJson(Map<String, dynamic> j) => WardrobeItem(
    itemId: j['itemId'] as String,
    slot: j['slot'] as String,
    label: j['label'] as String,
    color: j['color'] as String? ?? '',
    image: j['image'] as String,
    category: j['category'] as String?,
    layer: j['layer'] as String?,
    pattern: j['pattern'] as String?,
    materialGuess: j['materialGuess'] as String?,
    memo: j['memo'] as String?,
    createdAt: j['createdAt'] == null
        ? null
        : DateTime.parse(j['createdAt'] as String),
  );

  final String itemId;

  /// outer / top / bottom / dress / shoes / bag / accessory
  final String slot;
  final String label;
  final String color;

  /// 画像の口 (`/v1/wardrobe/{itemId}/image`)。[ApiClient.image] で読む。
  final String image;
  final String? category;
  final String? layer;
  final String? pattern;
  final String? materialGuess;
  final String? memo;
  final DateTime? createdAt;
}

class TodayOutfit {
  const TodayOutfit({
    required this.date,
    required this.image,
    required this.items,
    this.jobId,
    this.itemNotes = const [],
  });

  factory TodayOutfit.fromJson(Map<String, dynamic> j) => TodayOutfit(
    date: j['date'] as String,
    image: j['image'] as String,
    jobId: j['jobId'] as String?,
    itemNotes: (j['itemNotes'] as List? ?? const [])
        .whereType<String>()
        .toList(),
    items: [
      for (final i in (j['items'] as List? ?? const []))
        WardrobeItem.fromJson(i as Map<String, dynamic>),
    ],
  );

  final String date;
  final String? jobId;
  final List<String> itemNotes;

  /// 処理後の着姿の画像の口 (`/v1/outfits/today/image`)。
  final String image;
  final List<WardrobeItem> items;
}

/// 近くのコーデのカードの中の服 1 着。番号はこのカードの中だけで通じる。
class CardItem {
  const CardItem({
    required this.cardItemId,
    required this.slot,
    required this.label,
    required this.color,
    required this.image,
    this.category,
    this.layer,
    this.pattern,
    this.materialGuess,
    this.memo = '',
  });

  factory CardItem.fromJson(Map<String, dynamic> j) => CardItem(
    cardItemId: j['cardItemId'] as String,
    slot: j['slot'] as String,
    label: j['label'] as String,
    color: j['color'] as String? ?? '',
    image: j['image'] as String,
    category: j['category'] as String?,
    layer: j['layer'] as String?,
    pattern: j['pattern'] as String?,
    materialGuess: j['materialGuess'] as String?,
    memo: j['memo'] as String? ?? '',
  );

  final String cardItemId;
  final String slot;
  final String label;
  final String color;
  final String image;
  final String? category;
  final String? layer;
  final String? pattern;
  final String? materialGuess;
  final String memo;
}

/// 近くのコーデ 1 人分。使い捨てで、見てから 30 分で切れる。uid などは持たない。
class NearbyCard {
  const NearbyCard({
    required this.cardId,
    required this.image,
    required this.seenAgoSec,
    required this.expiresAt,
    required this.items,
    this.isDemo = false,
  });

  factory NearbyCard.fromJson(Map<String, dynamic> j) => NearbyCard(
    cardId: j['cardId'] as String,
    image: j['image'] as String,
    seenAgoSec: j['seenAgoSec'] as int? ?? 0,
    expiresAt: DateTime.parse(j['expiresAt'] as String),
    isDemo: j['isDemo'] as bool? ?? false,
    items: [
      for (final i in (j['items'] as List? ?? const []))
        CardItem.fromJson(i as Map<String, dynamic>),
    ],
  );

  final String cardId;

  /// 頭と背景を消した着姿 (透かし入り) の画像の口
  final String image;

  /// 受け取ってからの秒数 (例 180 → 3 分前)
  final int seenAgoSec;
  final DateTime expiresAt;
  final bool isDemo;
  final List<CardItem> items;
}

class NearbyResult {
  const NearbyResult({required this.cards, required this.viewerPublishing});

  factory NearbyResult.fromJson(Map<String, dynamic> j) => NearbyResult(
    cards: [
      for (final c in (j['cards'] as List? ?? const []))
        NearbyCard.fromJson(c as Map<String, dynamic>),
    ],
    viewerPublishing: j['viewerPublishing'] as bool? ?? false,
  );

  final List<NearbyCard> cards;

  /// false の時、カードは空で返る (お互いさま)。画面で公開を促す
  final bool viewerPublishing;
}

class SameItem {
  const SameItem(this.index, this.wardrobeItem, this.reason);

  factory SameItem.fromJson(Map<String, dynamic> json) => SameItem(
    json['index'] as int,
    WardrobeItem.fromJson(json['wardrobeItem'] as Map<String, dynamic>),
    json['reason'] as String? ?? '',
  );

  final int index;
  final WardrobeItem wardrobeItem;
  final String reason;
}

class OutfitCombination {
  const OutfitCombination(this.wardrobeItemIds, this.reason);

  factory OutfitCombination.fromJson(Map<String, dynamic> json) =>
      OutfitCombination(
        List<String>.from(json['wardrobeItemIds'] as List),
        json['reason'] as String,
      );

  final List<String> wardrobeItemIds;
  final String reason;
}

class MatchResult {
  const MatchResult(
    this.combos,
    this.missing,
    this.similarOwned, {
    this.precomputed = false,
  });

  factory MatchResult.fromJson(Map<String, dynamic> json) {
    final similar = json['similarOwned'] as Map<String, dynamic>?;
    return MatchResult(
      [
        for (final combo in json['combos'] as List)
          OutfitCombination.fromJson(combo as Map<String, dynamic>),
      ],
      (json['missing'] as Map<String, dynamic>?)?['description'] as String?,
      similar == null
          ? null
          : (
              itemId: similar['wardrobeItemId'] as String,
              reason: similar['reason'] as String,
            ),
      precomputed: json['precomputed'] as bool? ?? false,
    );
  }

  /// AI を止めている時に返る、事前に作った結果。画面にそう出す
  final bool precomputed;
  final List<OutfitCombination> combos;
  final String? missing;
  final ({String itemId, String reason})? similarOwned;
}

class TryOnResult {
  const TryOnResult(this.image, this.label);

  /// AI を止めている時に返る事前の画像は、今作った物に見せないようラベルに書く
  factory TryOnResult.fromJson(Map<String, dynamic> json) => TryOnResult(
    json['image'] as String,
    json['precomputed'] == true
        ? '${json['label']} (AI を止めているため、事前に作った画像です)'
        : json['label'] as String,
  );

  final String image;
  final String label;
}
