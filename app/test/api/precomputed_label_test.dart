import 'package:flutter_test/flutter_test.dart';

import 'package:app/api/api_models.dart';

/// 事前に作った結果 (AI を止めている時だけ返る) は、今作った物に見せない (2026-11-10)。
void main() {
  test('事前に作った着用イメージはラベルにそう書く', () {
    final live = TryOnResult.fromJson({
      'image': '/v1/tryon/t_1/image',
      'label': 'AI による着用イメージ',
      'precomputed': false,
    });
    final pre = TryOnResult.fromJson({
      'image': '/v1/tryon/t_2/image',
      'label': 'AI による着用イメージ',
      'precomputed': true,
    });
    expect(live.label, 'AI による着用イメージ');
    expect(pre.label, contains('事前に作った'));
  });

  test('照合の結果は事前に作った物かを持つ', () {
    Map<String, dynamic> body(bool pre) => {
      'combos': [],
      'missing': null,
      'similarOwned': null,
      'precomputed': pre,
    };
    expect(MatchResult.fromJson(body(true)).precomputed, isTrue);
    expect(MatchResult.fromJson(body(false)).precomputed, isFalse);
  });
}
