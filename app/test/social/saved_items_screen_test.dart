import 'dart:convert';

import 'package:app/api/api_client.dart';
import 'package:app/social/saved_items_screen.dart';
import 'package:app/social/social_activity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('保存を解除すると一覧が更新される', (tester) async {
    var removed = false;
    final activity = SocialActivity(
      api: ApiClient(
        idToken: () async => 'test-token',
        httpClient: MockClient((request) async {
          if (request.method == 'DELETE') {
            expect(request.url.path, '/v1/saves/s_test');
            removed = true;
            return http.Response('', 204);
          }
          expect(request.url.path, '/v1/saves');
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'items': [
                  if (!removed)
                    {'saveId': 's_test', 'slot': 'top', 'label': 'シャツ'},
                ],
              }),
            ),
            200,
          );
        }),
      ),
    );
    addTearDown(activity.dispose);
    await tester.pumpWidget(
      MaterialApp(home: SavedItemsScreen(activity: activity)),
    );
    await tester.pumpAndSettle();
    expect(find.text('保存したアイテム'), findsOneWidget);
    await tester.tap(find.text('シューズ'));
    await tester.pumpAndSettle();
    expect(find.text('シャツ'), findsNothing);
    await tester.tap(find.text('すべて'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('シャツ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存を解除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('解除'));
    await tester.pumpAndSettle();

    expect(removed, isTrue);
    expect(find.text('保存したアイテムはありません'), findsOneWidget);
    expect(find.text('保存を解除できませんでした'), findsNothing);
  });
}
