import 'dart:async';
import 'dart:convert';

import 'package:app/api/api_client.dart';
import 'package:app/api/api_models.dart';
import 'package:app/app/app_loading.dart';
import 'package:app/capture/processed_outfit_screen.dart';
import 'package:app/register/outfit_job.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _day = '2026-11-08';
const _jobId = 'job_abcdef12';
const _image = '/v1/outfits/today/image';
const _bag = WardrobeItem(
  itemId: 'w_bag',
  slot: 'bag',
  label: 'トートバッグ',
  color: '生成り',
  image: '/v1/wardrobe/w_bag/image',
);

void main() {
  for (final editing in [false, true]) {
    testWidgets(editing ? '投稿済みのコーデは手持ちのIDを使って更新する' : '登録前に手持ちとメモを追加できる', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/aX8AAAAASUVORK5CYII=',
      );
      Map<String, dynamic>? saved;
      final suggestions = Completer<http.Response>();
      final api = ApiClient(
        idToken: () async => 'token',
        httpClient: MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/image')) return http.Response.bytes(png, 200);
          if (!editing && path == '/v1/jobs/$_jobId/same-items') {
            return suggestions.future;
          }
          final result = switch (path) {
            '/v1/wardrobe' => {
              'items': [
                {
                  'itemId': _bag.itemId,
                  'slot': _bag.slot,
                  'label': _bag.label,
                  'color': _bag.color,
                  'image': _bag.image,
                },
              ],
            },
            '/v1/outfits/today' when request.method == 'PUT' => {
              'date': _day,
              'jobId': _jobId,
              'image': _image,
              'items': [],
              'itemNotes': ['時計'],
            },
            _ => throw StateError(
              'Unexpected request: ${request.method} $path',
            ),
          };
          if (request.method == 'PUT') saved = jsonDecode(request.body);
          return http.Response.bytes(utf8.encode(jsonEncode(result)), 200);
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push<TodayOutfit>(
                context,
                MaterialPageRoute(
                  builder: (_) => editing
                      ? ProcessedOutfitScreen.edit(
                          api: api,
                          jobId: _jobId,
                          outfit: const TodayOutfit(
                            date: _day,
                            image: _image,
                            items: [_bag],
                          ),
                          heroTag: null,
                        )
                      : ProcessedOutfitScreen(
                          api: api,
                          jobId: _jobId,
                          outfit: const OutfitJob(
                            status: 'succeeded',
                            outfitImage: _image,
                            items: [
                              OutfitJobItem(
                                index: 0,
                                image: _image,
                                slot: 'outer',
                                label: 'ジャケット',
                              ),
                            ],
                          ),
                        ),
                ),
              ),
              child: const Text('開く'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('開く'));
      if (!editing) {
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('手持ちに同じ服があるか確認しています'), findsOneWidget);
        expect(find.byType(AppLoadingIndicator), findsOneWidget);
        final memo = find.byType(TextField);
        final add = find.byType(OutlinedButton);
        final save = find.byType(FilledButton);
        final memoPosition = tester.getRect(memo);
        final addPosition = tester.getRect(add);
        final savePosition = tester.getRect(save);
        expect(addPosition.height, 56);
        expect(savePosition.height, 56);

        suggestions.complete(http.Response('{"items":[]}', 200));
        await tester.pumpAndSettle();
        expect(find.text('このアイテムと同じ服は手持ちにありません'), findsOneWidget);
        expect(find.byType(AppLoadingIndicator), findsNothing);
        expect(tester.getRect(memo), memoPosition);
        expect(tester.getRect(add), addPosition);
        expect(tester.getRect(save), savePosition);

        await tester.tap(find.text('アイテムを追加'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(_bag.label));
        await tester.pumpAndSettle();
      } else {
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('アイテムを追加'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新しく追加'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '時計');
      await tester.pump();
      await tester.tap(find.text('メモで追加'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(editing ? '変更を保存' : 'コーデを投稿'));
      await tester.pumpAndSettle();
      expect(saved, {
        'jobId': _jobId,
        if (editing) 'editDate': _day,
        'items': [
          if (!editing) {'index': 0},
          {'wardrobeItemId': _bag.itemId, 'memo': ''},
          {'memo': '時計'},
        ],
      });
    });
  }
}
