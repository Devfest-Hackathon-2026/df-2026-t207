import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lib/capture/outfit_photo_review_screen.dart';

void main() {
  testWidgets('写真を確認して投稿できる', (tester) async {
    var confirmed = false;
    final image = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/aX8AAAAASUVORK5CYII=',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: OutfitPhotoReviewScreen(
          photoBytes: image,
          isDemo: true,
          onRetake: () {},
          onConfirm: () => confirmed = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('撮りなおす'), findsOneWidget);
    await tester.tap(find.text('投稿'));
    expect(confirmed, isTrue);
  });
}
