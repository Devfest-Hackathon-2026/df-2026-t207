import 'dart:convert';

import 'package:app/capture/outfit_items_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/friend_preview_images.dart';

void main() {
  testWidgets('候補の切り替えで一覧とボタンを固定し、外す確認には服の画像を出す', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final thumbnail = previewJacket;
    await tester.pumpWidget(
      MaterialApp(
        home: OutfitItemsReviewScreen(
          items: [
            OutfitReviewItem(index: 0, label: 'アウター', image: thumbnail),
            OutfitReviewItem(index: 1, label: 'シューズ'),
          ],
          onRemove: (_) {},
          onAdd: () {},
          itemAccessory: (index) => index == 0
              ? const Text('手持ちのジャケットを使う')
              : const Text('このアイテムと同じ服は手持ちにありません'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final strip = find.byType(ListView);
    final position = tester.getRect(strip);
    final add = find.byType(OutlinedButton);
    final save = find.byType(FilledButton);
    final addPosition = tester.getRect(add);
    final savePosition = tester.getRect(save);
    final memo = find.byType(TextField);
    final memoPosition = tester.getRect(memo);
    await tester.tap(find.text('シューズ'));
    await tester.pumpAndSettle();
    expect(tester.getRect(strip), position);
    expect(tester.getRect(add), addPosition);
    expect(tester.getRect(save), savePosition);
    expect(tester.getRect(memo), memoPosition);

    await tester.tap(find.byTooltip('アウターを外す'));
    await tester.pumpAndSettle();
    final sheet = find.byType(BottomSheet);
    final preview = find.descendant(of: sheet, matching: find.byType(Image));
    expect(tester.widget<Image>(preview).image, thumbnail);
  });

  testWidgets('アイテムごとにメモを切り替えて入力できる', (tester) async {
    final changed = <int, String>{};
    final image = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/aX8AAAAASUVORK5CYII=',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: OutfitItemsReviewScreen(
          outfitImageBytes: image,
          items: const [
            OutfitReviewItem(index: 0, label: 'アウター'),
            OutfitReviewItem(index: 1, label: 'トップス'),
          ],
          onRemove: (_) {},
          onAdd: () {},
          onContinue: () {},
          onMemoChanged: (index, memo) => changed[index] = memo,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('アウターのメモ'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'ブランドA');
    await tester.tap(find.text('トップス'));
    await tester.pumpAndSettle();
    expect(find.text('トップスのメモ'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'ブランドB');
    await tester.tap(find.text('アウター'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'ブランドA',
    );
    expect(changed, {0: 'ブランドA', 1: 'ブランドB'});
  });
}
