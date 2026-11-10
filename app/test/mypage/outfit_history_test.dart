import 'package:flutter_test/flutter_test.dart';

import 'package:app/mypage/outfit_history.dart';

/// dailyOutfits を手で置く。読んだ範囲を覚える
class _FakeSource implements OutfitHistorySource {
  _FakeSource(this.docs);

  final Map<String, Map<String, dynamic>> docs;
  final ranges = <(String, String)>[];

  @override
  Future<Map<String, Map<String, dynamic>>> range(
    String uid,
    String fromId,
    String toId,
  ) async {
    ranges.add((fromId, toId));
    return {
      for (final entry in docs.entries)
        if (entry.key.compareTo(fromId) >= 0 && entry.key.compareTo(toId) <= 0)
          entry.key: entry.value,
    };
  }

  @override
  Future<int> count(String uid) async =>
      docs.values.where((d) => (d['image'] as String? ?? '').isNotEmpty).length;
}

Map<String, dynamic> _posted(String job) => {
  'image': 'users/u1/jobs/$job/outfit.png',
  'outfitImage': '/v1/jobs/$job/images/outfit',
};

void main() {
  test('月の初日から末日までに絞って読み、投稿時点の写しから服を出す', () async {
    final source = _FakeSource({
      '2026-10-31': _posted('job_oct31xx'),
      '2026-11-03': {
        ..._posted('job_nov03xx'),
        'items': ['w_coat'],
        'snapshot': [
          {
            'itemId': 'w_coat',
            'slot': 'outer',
            'label': 'ステンカラーコート',
            'color': 'ベージュ',
            'image': '/v1/jobs/job_nov03xx/images/item-0',
            'memo': '古着',
          },
          {'itemId': 'w_broken'}, // 欠けた写しは飛ばす
        ],
        'itemNotes': ['ネックレス', ' '],
      },
      // 公開を切り替えただけの日 (着姿が無い) は記録に入れない
      '2026-11-05': {'publishing': true},
      '2026-12-01': _posted('job_dec01xx'),
    });

    final november = await OutfitHistory(source).month('u1', 2026, 11);

    expect(source.ranges.single, ('2026-11-01', '2026-11-30'));
    expect(november.keys, [DateTime.utc(2026, 11, 3)]);
    final day = november[DateTime.utc(2026, 11, 3)]!;
    expect(day.image, '/v1/jobs/job_nov03xx/images/outfit');
    expect(day.snapshot!.single.label, 'ステンカラーコート');
    expect(day.snapshot!.single.memo, '古着');
    expect(day.notes, ['ネックレス']);
  });

  test('outfitImage が無い古い記録は、Storage の置き場から画像の口を作る', () {
    final outfit = CalendarOutfit.fromDocument({
      'image': 'users/u1/jobs/job_oldxxxxx/outfit.png',
      'items': ['w_a'],
    })!;
    expect(outfit.image, '/v1/jobs/job_oldxxxxx/images/outfit');
    expect(outfit.snapshot, isNull, reason: '写しが無い時は手持ちから探す');
    expect(outfit.itemIds, ['w_a']);
  });

  test('連続記録は 31 日ずつ前へ読み、今日がまだなら昨日から数える', () async {
    final today = DateTime.utc(2026, 11, 9);
    final docs = <String, Map<String, dynamic>>{};
    // 11/8 から 40 日続けて投稿、その前は空き
    for (var i = 1; i <= 40; i++) {
      docs[dailyOutfitId(today.subtract(Duration(days: i)))] = _posted(
        'job_${i}xxxxxxx',
      );
    }
    docs['2026-09-01'] = _posted('job_earlyxxx');
    final source = _FakeSource(docs);

    final streak = await OutfitHistory(source).streak('u1', today: today);

    expect(streak, 40);
    expect(source.ranges, [
      ('2026-10-10', '2026-11-09'),
      ('2026-09-09', '2026-10-09'),
    ]);
  });

  test('日本時間の今日は、UTC の日付がまだ前日でも日本の日付になる', () {
    expect(
      todayInJapan(DateTime.utc(2026, 11, 8, 15, 30)),
      DateTime.utc(2026, 11, 9),
    );
    expect(dailyOutfitId(DateTime.utc(2026, 1, 5)), '2026-01-05');
  });
}
