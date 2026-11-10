import 'package:app/api/api_models.dart';
import 'package:app/viewer/nearby_outfits_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 「模擬」の印は、模擬の近くの人を出している時だけ (人がいない投稿の案内の画面では何が模擬か分からない)。
Widget _screen(NearbyResult result) => MaterialApp(
  home: NearbyOutfitsScreen(
    loadNearby: () async => result,
    imageFor: (_) => null,
    isSimulated: true,
  ),
);

NearbyCard _card() => NearbyCard.fromJson({
  'cardId': 'c_1',
  'image': '/v1/cards/c_1/image',
  'seenAgoSec': 0,
  'expiresAt': '2099-01-01T00:00:00+09:00',
  'items': [],
});

void main() {
  testWidgets('近くの人がいない時は「デモ」を出さない', (tester) async {
    await tester.pumpWidget(
      _screen(const NearbyResult(cards: [], viewerPublishing: false)),
    );
    await tester.pumpAndSettle();
    expect(find.text('デモ'), findsNothing);
  });

  testWidgets('模擬の近くの人を出している時は「デモ」を出す', (tester) async {
    await tester.pumpWidget(
      _screen(NearbyResult(cards: [_card()], viewerPublishing: true)),
    );
    await tester.pumpAndSettle();
    expect(find.text('デモ'), findsOneWidget);
  });
}
