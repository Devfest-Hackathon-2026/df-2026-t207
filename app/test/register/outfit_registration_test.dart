import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../lib/api/api_client.dart';
import '../../lib/register/outfit_job.dart';
import '../../lib/register/outfit_registration_flow.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);
final _photo = utf8.encode('jpeg');

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// jobs の文書を手で流す
class _FakeJobs implements OutfitJobSource {
  final controller = StreamController<OutfitJob?>.broadcast();
  String? watchedUid;
  String? watchedJobId;

  @override
  Stream<OutfitJob?> watch(String uid, String jobId) {
    watchedUid = uid;
    watchedJobId = jobId;
    return controller.stream;
  }
}

Map<String, dynamic> _succeeded(String jobId) => {
      'status': 'succeeded',
      'progress': 1,
      'result': {
        'outfitImage': '/v1/jobs/$jobId/images/outfit',
        'items': [
          {'index': 0, 'image': '/v1/jobs/$jobId/images/item-0', 'slot': 'outer', 'label': 'デニムジャケット', 'points': []},
          {'index': 1, 'image': '/v1/jobs/$jobId/images/item-1', 'slot': 'bottom', 'label': '黒のスラックス', 'points': []},
        ],
      },
    };

void main() {
  test('送る前に購読を始め、vision に写真と jobId を送り、終わった jobs を返す', () async {
    final jobs = _FakeJobs();
    final progress = <String>[];
    late http.MultipartRequest sent;
    final api = ApiClient(
      idToken: () async => 'tok',
      baseUrl: 'https://api.example',
      visionBaseUrl: 'https://vision.example/',
      httpClient: MockClient.streaming((request, body) async {
        sent = request as http.MultipartRequest;
        expect(jobs.watchedJobId, isNotNull, reason: '送る前に購読している');
        jobs.controller.add(const OutfitJob(status: 'masking', progress: 0.2));
        jobs.controller.add(OutfitJob.fromJson(_succeeded(jobs.watchedJobId!)));
        return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode({'jobId': jobs.watchedJobId, 'status': 'succeeded'}))),
          200,
        );
      }),
    );

    final done = await runOutfitJob(
      api: api,
      jobs: jobs,
      uid: 'u1',
      photo: _photo,
      onProgress: (j) => progress.add(j.status),
    );

    expect(sent.url.toString(), 'https://vision.example/v1/outfits/process');
    expect(sent.headers['Authorization'], 'Bearer tok');
    expect(sent.fields['jobId'], done.jobId);
    expect(RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(done.jobId), isTrue);
    expect(sent.files.single.field, 'photo');
    expect(jobs.watchedUid, 'u1');
    expect(progress, ['masking', 'succeeded']);
    expect(done.job.items.map((i) => i.label), ['デニムジャケット', '黒のスラックス']);
  });

  test('処理に失敗したら jobs の理由の文で知らせる', () async {
    final jobs = _FakeJobs();
    final api = ApiClient(
      idToken: () async => 'tok',
      visionBaseUrl: 'https://vision.example',
      httpClient: MockClient((_) async {
        jobs.controller.add(const OutfitJob(
          status: 'failed',
          errorCode: 'face_detected',
          errorMessage: '顔が見えているため公開できません。撮りなおしてください',
        ));
        return _json({'jobId': jobs.watchedJobId, 'status': 'failed'});
      }),
    );
    await expectLater(
      runOutfitJob(api: api, jobs: jobs, uid: 'u1', photo: _photo),
      throwsA(isA<OutfitJobException>()
          .having((e) => e.code, 'code', 'face_detected')
          .having((e) => e.message, 'message', contains('撮りなおして'))),
    );
  });

  test('匿名ログインで断られたら、Google でのログインが要ると知らせる', () async {
    final api = ApiClient(
      idToken: () async => 'tok',
      visionBaseUrl: 'https://vision.example',
      httpClient: MockClient((_) async => _json({
            'error': {'code': 'forbidden', 'message': 'forbidden'},
          }, 403)),
    );
    await expectLater(
      runOutfitJob(api: api, jobs: _FakeJobs(), uid: 'u1', photo: _photo),
      throwsA(isA<OutfitJobException>().having((e) => e.message, 'message', contains('Google'))),
    );
  });

  testWidgets('処理の後に服を確かめ、外した服を除いてメモと一緒に登録する', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final jobs = _FakeJobs();
    Map<String, dynamic>? registered;
    final api = ApiClient(
      idToken: () async => 'tok',
      baseUrl: 'https://api.example',
      visionBaseUrl: 'https://vision.example',
      httpClient: MockClient((r) async {
        if (r.url.host == 'vision.example') {
          jobs.controller.add(OutfitJob.fromJson(_succeeded(jobs.watchedJobId!)));
          return _json({'jobId': jobs.watchedJobId, 'status': 'succeeded'});
        }
        if (r.method == 'PUT' && r.url.path == '/v1/outfits/today') {
          registered = jsonDecode(r.body) as Map<String, dynamic>;
          return _json({'date': '2026-11-08', 'image': '/v1/outfits/today/image', 'items': []});
        }
        return http.Response.bytes(_png, 200, headers: {'content-type': 'image/png'});
      }),
    );

    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await Navigator.of(context).push<bool>(MaterialPageRoute(
              builder: (_) => OutfitRegistrationFlow(
                api: api,
                jobs: jobs,
                uid: () async => 'u1',
                photo: _png,
              ),
            ));
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    // multipart の送信と画像の読み込みは本物の非同期で進む
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();

    expect(find.text('デニムジャケット'), findsWidgets);
    await tester.tap(find.byTooltip('黒のスラックスを外す'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('黒のスラックスを外す'), findsOneWidget);
    await tester.tap(find.byTooltip('黒のスラックスを外す'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('外す'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('黒のスラックスを外す'), findsNothing);
    await tester.enterText(find.byType(TextField), 'ブランドA');
    await tester.tap(find.text('投稿する'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();

    expect(registered!['jobId'], jobs.watchedJobId);
    expect(registered!['items'], [
      {'index': 0, 'memo': 'ブランドA'},
    ]);
    expect(result, isTrue);
  });
}
