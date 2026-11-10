import 'package:app/social/friend_outfit_items.dart';
import 'package:app/social/friend_outfit_post_body.dart';
import 'package:app/viewer/nearby_outfits_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/friend_preview_images.dart';

void main() {
  testWidgets('投稿画像の表示位置に関わらず近接共有と同じ詳細を開く', (tester) async {
    const channel = MethodChannel('jp.dfhack26.app/viewer_security');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    await tester.binding.setSurfaceSize(const Size(390, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              FriendOutfitPostBody(
                image: previewOutfit,
                imageLabel: '投稿画像',
                items: [FriendOutfitItem(slot: 'outer', label: 'ワークジャケット')],
                isGenerated: false,
              ),
              SizedBox(height: 600),
            ],
          ),
        ),
      ),
    );

    final tile = find.text('アウター');
    await tester.tap(tile);
    await tester.pumpAndSettle();
    final detail = find.byType(NearbyOutfitsScreen);
    expect(detail, findsOneWidget);
    expect(find.text('ワークジャケット'), findsOneWidget);

    await tester.tap(find.byTooltip('戻る'));
    await tester.pumpAndSettle();
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(410);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(detail, findsOneWidget);
    expect(find.text('ワークジャケット'), findsOneWidget);
  });
}
