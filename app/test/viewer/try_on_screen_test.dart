import 'package:app/api/api_client.dart';
import 'package:app/api/api_models.dart';
import 'package:app/viewer/try_on_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/friend_preview_images.dart';

const _portrait = AssetImage('assets/images/login_illustration.png');

class _TryOnApi extends ApiClient {
  _TryOnApi() : super(idToken: () async => null);

  @override
  Future<TryOnResult> tryOn(
    String cardId,
    String cardItemId,
    List<String> wardrobeItemIds, {
    bool regenerate = false,
  }) async => const TryOnResult('/result', 'AI による着用イメージ');

  @override
  ImageProvider tryOnImage(String path) => _portrait;

  @override
  ImageProvider image(String path, {Object? version}) => previewJacket;
}

void main() {
  testWidgets('縦長の着用画像と操作を一画面に収め、4点の一覧だけ横に動かせる', (tester) async {
    const screen = Size(320, 568);
    await tester.binding.setSurfaceSize(screen);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const ids = ['top', 'bottom', 'shoes'];
    await tester.pumpWidget(
      MaterialApp(
        home: TryOnScreen(
          api: _TryOnApi(),
          cardId: 'card',
          item: const CardItem(
            cardItemId: 'jacket',
            slot: 'outer',
            label: 'ジャケット',
            color: '',
            image: '/jacket',
          ),
          wardrobeItemIds: ids,
          wardrobe: Future.value({
            for (final id in ids)
              id: WardrobeItem(
                itemId: id,
                slot: id,
                label: id,
                color: '',
                image: '/$id',
              ),
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final image = find.byWidgetPredicate(
      (widget) => widget is Image && widget.image == _portrait,
    );
    final items = find.text('着用アイテム');
    final retry = find.widgetWithText(OutlinedButton, 'やり直す');
    expect(tester.widget<Image>(image).fit, BoxFit.contain);
    expect(tester.getRect(image).bottom, lessThan(tester.getRect(items).top));
    expect(tester.getRect(retry).bottom, lessThanOrEqualTo(screen.height));

    final strip = find.byType(Scrollable);
    final position = tester.state<ScrollableState>(strip).position;
    expect(position.axis, Axis.horizontal);
    expect(position.maxScrollExtent, greaterThan(0));
    final buttonPosition = tester.getRect(retry);
    await tester.drag(strip, const Offset(-100, 0));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));
    expect(tester.getRect(retry), buttonPosition);
  });
}
