import 'package:cloud_firestore/cloud_firestore.dart';

import '../api/api_models.dart';

/// コーデカレンダーの 1 日。`users/{uid}/dailyOutfits/{date}` の、投稿した時点の写し (M14)。
/// 手持ちから服を消しても、その日の服を投稿時点のまま見られる。
class CalendarOutfit {
  const CalendarOutfit({
    required this.image,
    this.snapshot,
    this.itemIds = const [],
    this.notes = const [],
    this.memos = const {},
  });

  /// 着姿の画像の口 (`/v1/jobs/{jobId}/images/outfit`)
  final String image;

  /// 投稿した時点の服の写し。写しが無い古い記録は null (手持ちから探す)
  final List<WardrobeItem>? snapshot;
  final List<String> itemIds;

  /// 写真の無いアイテムのメモ
  final List<String> notes;

  /// 写しが無い古い記録の、コーデ専用のメモ (itemId → メモ)
  final Map<String, String> memos;

  static final _storageImage = RegExp(
    r'^users/[^/]+/jobs/([A-Za-z0-9_-]{8,64})/outfit\.png$',
  );

  /// 着姿の画像が無い文書 (公開を切り替えただけの日など) は null
  static CalendarOutfit? fromDocument(Map<String, dynamic> data) {
    final image = switch ((data['outfitImage'], data['image'])) {
      (final String api, _) when api.startsWith('/v1/jobs/') => api,
      // outfitImage を書く前に登録した日は、Storage の置き場から口を作る
      (_, final String path) => switch (_storageImage.firstMatch(path)) {
        final match? => '/v1/jobs/${match.group(1)}/images/outfit',
        null => null,
      },
      _ => null,
    };
    if (image == null) return null;
    return CalendarOutfit(
      image: image,
      snapshot: switch (data['snapshot']) {
        final List snapshot => [
          for (final item in snapshot.whereType<Map>())
            ?_snapshotItem(Map<String, dynamic>.from(item)),
        ],
        _ => null,
      },
      itemIds: (data['items'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      notes: (data['itemNotes'] as List? ?? const [])
          .whereType<String>()
          .where((note) => note.trim().isNotEmpty)
          .toList(),
      memos: {
        for (final entry
            in (data['itemMemos'] as List? ?? const []).whereType<Map>())
          if (entry['itemId'] is String && entry['memo'] is String)
            entry['itemId'] as String: entry['memo'] as String,
      },
    );
  }

  static WardrobeItem? _snapshotItem(Map<String, dynamic> json) {
    try {
      return WardrobeItem.fromJson(json);
    } catch (_) {
      return null; // 欠けた写しは、その服だけ飛ばす
    }
  }
}

/// 日本時間の日付を表す UTC の年月日 (カレンダーのキー)
DateTime calendarDate(int year, int month, int day) =>
    DateTime.utc(year, month, day);

/// `dailyOutfits` の文書の id (`YYYY-MM-DD`)
String dailyOutfitId(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// 今日 (日本時間) をカレンダーのキーの形で
DateTime todayInJapan([DateTime? now]) {
  final jst = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 9));
  return calendarDate(jst.year, jst.month, jst.day);
}

/// `dailyOutfits` を読む口。本物は Firestore、試験では差し替える。
abstract class OutfitHistorySource {
  /// id が [fromId] 以上 [toId] 以下の文書 (id → 中身)
  Future<Map<String, Map<String, dynamic>>> range(
    String uid,
    String fromId,
    String toId,
  );

  /// 着姿の画像がある文書の数 (投稿数)
  Future<int> count(String uid);
}

class FirestoreOutfitHistorySource implements OutfitHistorySource {
  FirestoreOutfitHistorySource([FirebaseFirestore? db]) : _db = db;

  final FirebaseFirestore? _db;

  CollectionReference<Map<String, dynamic>> _days(String uid) =>
      (_db ?? FirebaseFirestore.instance).collection('users/$uid/dailyOutfits');

  @override
  Future<Map<String, Map<String, dynamic>>> range(
    String uid,
    String fromId,
    String toId,
  ) async {
    final snapshot = await _days(uid)
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: fromId)
        .where(FieldPath.documentId, isLessThanOrEqualTo: toId)
        .get();
    return {for (final doc in snapshot.docs) doc.id: doc.data()};
  }

  @override
  Future<int> count(String uid) async {
    // 公開を切り替えただけの日は image が無いので数えない
    final snapshot = await _days(uid)
        .where('image', isGreaterThan: '')
        .count()
        .get();
    return snapshot.count ?? 0;
  }
}

/// カレンダーと投稿数・連続記録の読み方。全部を一度に読まず、月ごとに日付で絞って読む。
class OutfitHistory {
  OutfitHistory(this.source);

  final OutfitHistorySource source;

  /// [year] 年 [month] 月の記録
  Future<Map<DateTime, CalendarOutfit>> month(
    String uid,
    int year,
    int month,
  ) async {
    final first = calendarDate(year, month, 1);
    final last = calendarDate(year, month + 1, 0);
    final docs = await source.range(
      uid,
      dailyOutfitId(first),
      dailyOutfitId(last),
    );
    return {
      for (final entry in docs.entries)
        ?DateTime.tryParse('${entry.key}T00:00:00Z'):
            ?CalendarOutfit.fromDocument(entry.value),
    };
  }

  Future<int> postCount(String uid) => source.count(uid);

  /// 今日 (まだなら昨日) から続けて投稿した日数。31 日ずつ前へ読み、途切れたら止める
  Future<int> streak(String uid, {DateTime? today}) async {
    const day = Duration(days: 1);
    const window = 31;
    final start = today ?? todayInJapan();
    var streak = 0;
    var cursor = start;
    var skippedToday = false;
    while (true) {
      final from = cursor.subtract(const Duration(days: window - 1));
      final docs = await source.range(
        uid,
        dailyOutfitId(from),
        dailyOutfitId(cursor),
      );
      bool posted(DateTime date) =>
          CalendarOutfit.fromDocument(docs[dailyOutfitId(date)] ?? const {}) !=
          null;
      while (!cursor.isBefore(from)) {
        if (posted(cursor)) {
          streak++;
        } else if (cursor == start && !skippedToday) {
          skippedToday = true; // 今日まだ投稿していなくても、昨日までの連続は数える
        } else {
          return streak;
        }
        cursor = cursor.subtract(day);
        if (streak >= 3650) return streak; // 念のための上限 (10 年)
      }
    }
  }
}
