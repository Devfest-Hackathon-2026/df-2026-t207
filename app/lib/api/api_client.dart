import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;

import 'api_models.dart';
import 'social_models.dart';

/// `api` を呼ぶ部品。全部のリクエストに `Authorization: Bearer <ID トークン>` を付ける。
///
/// 住所は `--dart-define=API_BASE_URL=...` で替えられる (既定は配備済みの api)。
class ApiClient {
  ApiClient({
    required this.idToken,
    http.Client? httpClient,
    String? baseUrl,
    String? visionBaseUrl,
  }) : _http = httpClient ?? http.Client(),
       baseUrl = (baseUrl ?? defaultBaseUrl).replaceFirst(RegExp(r'/+$'), ''),
       visionBaseUrl = (visionBaseUrl ?? defaultVisionBaseUrl).replaceFirst(
         RegExp(r'/+$'),
         '',
       );

  /// 普段の api の URL (2026-11-09 から本物)。仮の api に戻す時は白井がこの URL の流れ先を替えるので、アプリは替えない
  static const defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api-591807217114.asia-northeast1.run.app',
  );

  /// 全身写真の処理だけを受けるサービスの接続先。
  static const defaultVisionBaseUrl = String.fromEnvironment(
    'VISION_BASE_URL',
    defaultValue: 'https://vision-591807217114.asia-northeast1.run.app',
  );

  /// 今の ID トークンを返す。ログインしていなければ null。
  final Future<String?> Function() idToken;
  final String baseUrl;
  final String visionBaseUrl;
  final http.Client _http;

  Future<Map<String, String>> _headers({bool json = false}) async {
    final token = await idToken();
    return {
      if (token != null) 'Authorization': 'Bearer $token',
      if (json) 'Content-Type': 'application/json',
    };
  }

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    final request = http.Request(method, _uri(path, query))
      ..headers.addAll(await _headers(json: body != null));
    if (body != null) request.body = jsonEncode(body);
    return _read(request);
  }

  Future<Map<String, dynamic>> _read(http.BaseRequest request) async {
    final response = await http.Response.fromStream(await _http.send(request));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.statusCode == 204 || response.bodyBytes.isEmpty) {
        return const {};
      }
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    }
    throw _error(response);
  }

  Future<Map<String, dynamic>> _sendPhoto(
    String method,
    Uri uri,
    Uint8List jpeg,
    Map<String, String> fields, {
    String field = 'photo',
    String filename = 'photo.jpg',
  }) async {
    final request = http.MultipartRequest(method, uri)
      ..headers.addAll(await _headers())
      ..fields.addAll(fields)
      ..files.add(
        http.MultipartFile.fromBytes(field, jpeg, filename: filename),
      );
    return _read(request);
  }

  ApiException _error(http.Response response) {
    try {
      final e =
          (jsonDecode(utf8.decode(response.bodyBytes)) as Map)['error'] as Map;
      return ApiException(
        response.statusCode,
        e['code'] as String,
        e['message'] as String,
      );
    } catch (_) {
      return ApiException(
        response.statusCode,
        'http_${response.statusCode}',
        'サーバに接続できませんでした',
      );
    }
  }

  Future<Me> getMe() async => Me.fromJson(await _send('GET', '/v1/me'));

  Future<Me> updateDisplayName(String name) async =>
      Me.fromJson(await _send('PATCH', '/v1/me', body: {'displayName': name}));

  Future<void> putProfileImage(Uint8List bytes, String crop) async {
    final png = bytes.length >= 8 && bytes[0] == 137 && bytes[1] == 80;
    await _sendPhoto(
      'PUT',
      _uri('/v1/me/profile-image'),
      bytes,
      {'crop': crop},
      field: 'image',
      filename: png ? 'profile.png' : 'profile.jpg',
    );
  }

  Future<void> deleteProfileImage() async {
    await _send('DELETE', '/v1/me/profile-image');
  }

  Future<List<FriendRecord>> getFriends() async => [
    for (final item in (await _send('GET', '/v1/friends'))['friends'] as List)
      FriendRecord.fromJson(item as Map<String, dynamic>),
  ];

  Future<FriendRequests> getFriendRequests() async {
    final data = await _send('GET', '/v1/friends/requests');
    List<FriendRequest> parse(String key) => [
      for (final item in data[key] as List)
        FriendRequest.fromJson(item as Map<String, dynamic>),
    ];
    return (incoming: parse('incoming'), outgoing: parse('outgoing'));
  }

  Future<FriendRequest> requestFriend(String code) async =>
      FriendRequest.fromJson(
        await _send('POST', '/v1/friends/requests', body: {'friendCode': code}),
      );

  Future<void> respondToFriendRequest(String id, {required bool accept}) async {
    final action = accept ? 'accept' : 'decline';
    await _send(
      'POST',
      '/v1/friends/requests/${Uri.encodeComponent(id)}/$action',
    );
  }

  Future<void> cancelFriendRequest(String id) async {
    await _send('DELETE', '/v1/friends/requests/${Uri.encodeComponent(id)}');
  }

  Future<void> removeFriend(String id) async {
    await _send('DELETE', '/v1/friends/${Uri.encodeComponent(id)}');
  }

  Future<void> setFriendLike(String id, bool liked) =>
      _setLike('friends', id, liked);

  Future<void> setCardLike(String id, bool liked) =>
      _setLike('cards', id, liked);

  Future<void> _setLike(String kind, String id, bool liked) async {
    await _send(
      liked ? 'PUT' : 'DELETE',
      '/v1/likes/$kind/${Uri.encodeComponent(id)}',
    );
  }

  Future<List<SavedItem>> getSaves() async => [
    for (final item in (await _send('GET', '/v1/saves'))['items'] as List)
      SavedItem.fromJson(item as Map<String, dynamic>),
  ];

  Future<SavedItem> saveCardItem(String cardId, String cardItemId) =>
      _saveItem({'cardId': cardId, 'cardItemId': cardItemId});

  Future<SavedItem> saveFriendItem(String friendId, int index) =>
      _saveItem({'friendId': friendId, 'index': index});

  Future<SavedItem> _saveItem(Map<String, Object> body) async =>
      SavedItem.fromJson(await _send('POST', '/v1/saves', body: body));

  Future<void> deleteSave(String id) async {
    await _send('DELETE', '/v1/saves/${Uri.encodeComponent(id)}');
  }

  Future<Notifications> getNotifications() async {
    final data = await _send('GET', '/v1/notifications');
    return (
      items: [
        for (final item in data['items'] as List)
          ApiNotice.fromJson(item as Map<String, dynamic>),
      ],
      unread: data['unread'] as int,
    );
  }

  Future<void> readNotifications([List<String>? ids]) async {
    await _send('POST', '/v1/notifications/read', body: {'ids': ?ids});
  }

  Future<void> setDeviceToken(String token, {required bool enabled}) async {
    await _send(
      enabled ? 'PUT' : 'DELETE',
      '/v1/me/devices',
      body: {'token': token},
    );
  }

  /// 結果の状態を返す。失敗理由は Firestore のジョブに書かれる。
  Future<String> processOutfit(String jobId, Uint8List jpeg) async {
    final result = await _sendPhoto(
      'POST',
      Uri.parse('$visionBaseUrl/v1/outfits/process'),
      jpeg,
      {'jobId': jobId},
    );
    return result['status'] as String;
  }

  /// 確認した服だけを、今日のコーデと手持ちに登録する。
  Future<TodayOutfit> registerTodayOutfit(
    String jobId,
    List<({int index, String memo})> items, {
    Map<int, String> sameAs = const {},
    List<({String? wardrobeItemId, String? memo})> addedItems = const [],
    String? editDate,
  }) async => TodayOutfit.fromJson(
    await _send(
      'PUT',
      '/v1/outfits/today',
      body: {
        'jobId': jobId,
        'editDate': ?editDate,
        'items': [
          for (final item in items)
            {
              'index': item.index,
              if (item.memo.trim().isNotEmpty) 'memo': item.memo.trim(),
              'sameAs': ?sameAs[item.index],
            },
          for (final item in addedItems)
            {
              'wardrobeItemId': ?item.wardrobeItemId,
              'memo': ?item.memo?.trim(),
            },
        ],
      },
    ),
  );

  Future<List<SameItem>> sameItems(String jobId) async {
    final result = await _send(
      'GET',
      '/v1/jobs/${Uri.encodeComponent(jobId)}/same-items',
    );
    return [
      for (final item in result['items'] as List)
        SameItem.fromJson(item as Map<String, dynamic>),
    ];
  }

  Future<NearbyCard> friendItemCard({
    required String friendId,
    required int index,
    required String date,
    required String slot,
    required String label,
    required String color,
  }) async => NearbyCard.fromJson(
    await _send(
      'POST',
      '/v1/friends/${Uri.encodeComponent(friendId)}/today/items/$index/card',
      body: {'date': date, 'slot': slot, 'label': label, 'color': color},
    ),
  );

  Future<MatchResult> match(String cardId, String cardItemId) async =>
      MatchResult.fromJson(
        await _send(
          'POST',
          '/v1/match',
          body: {'cardId': cardId, 'cardItemId': cardItemId},
        ),
      );

  Future<void> putTryOnPhoto(Uint8List jpeg) async {
    await _sendPhoto('PUT', _uri('/v1/me/photo'), jpeg, {
      'capturedWith': 'camera',
    });
  }

  Future<void> deleteTryOnPhoto() async {
    await _send('DELETE', '/v1/me/photo');
  }

  Future<TryOnResult> tryOn(
    String cardId,
    String cardItemId,
    List<String> wardrobeItemIds, {
    bool regenerate = false,
  }) async => TryOnResult.fromJson(
    await _send(
      'POST',
      '/v1/tryon',
      body: {
        'cardId': cardId,
        'cardItemId': cardItemId,
        'wardrobeItemIds': wardrobeItemIds,
        'regenerate': regenerate,
      },
    ),
  );

  /// 今日のコーデ。まだ登録していなければ null。
  Future<TodayOutfit?> getTodayOutfit() async {
    try {
      return TodayOutfit.fromJson(await _send('GET', '/v1/outfits/today'));
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<List<WardrobeItem>> getWardrobe({String? slot}) async {
    final j = await _send(
      'GET',
      '/v1/wardrobe',
      query: slot == null ? null : {'slot': slot},
    );
    return [
      for (final i in (j['items'] as List? ?? const []))
        WardrobeItem.fromJson(i as Map<String, dynamic>),
    ];
  }

  /// 手持ちから外す (`DELETE /v1/wardrobe/{itemId}`)
  Future<void> deleteWardrobeItem(String itemId) async {
    await _send('DELETE', '/v1/wardrobe/${Uri.encodeComponent(itemId)}');
  }

  /// 今日の公開を切り替える。`nearby` の時は匿名 ID の一覧も返る。
  Future<PublishState> setPublishing(bool publish) async =>
      PublishState.fromJson(
        await _send(
          'PUT',
          '/v1/publish',
          body: {'visibility': publish ? 'nearby' : 'private'},
        ),
      );

  /// 受け取った匿名 ID を、近くのコーデのカードに変える (`POST /v1/nearby`)。
  /// [sightings] は `nearbySightingsJson` で作った物。
  Future<NearbyResult> nearby(List<Map<String, Object>> sightings) async =>
      NearbyResult.fromJson(
        await _send('POST', '/v1/nearby', body: {'sightings': sightings}),
      );

  /// Web デモと Android の開発用の模擬検出。
  Future<NearbyResult> demoNearby() async => NearbyResult.fromJson(
    await _send('POST', '/v1/demo/nearby', body: const {}),
  );

  Future<void> blockCard(String cardId) async {
    await _send('POST', '/v1/blocks', body: {'cardId': cardId});
  }

  Future<void> reportCard(String cardId, String reason) async {
    await _send(
      'POST',
      '/v1/reports',
      body: {'cardId': cardId, 'reason': reason},
    );
  }

  /// 画像の口 (`/v1/...`) を同じ認証で読む画像。Web でも動くよう、バイトを取ってから描く。
  ImageProvider image(String path, {Object? version}) =>
      _ApiImage(this, path, version);

  /// 画面では着用画像の英字の帯を除き、日本語のラベルを別に表示する。
  ImageProvider tryOnImage(String path) =>
      _ApiImage(this, path, null, hideTryOnBand: true);

  Future<Uint8List> imageBytes(String path) async {
    final response = await _http.get(_uri(path), headers: await _headers());
    if (response.statusCode != 200) throw _error(response);
    return response.bodyBytes;
  }
}

@immutable
class _ApiImage extends ImageProvider<_ApiImage> {
  const _ApiImage(
    this.client,
    this.path,
    this.version, {
    this.hideTryOnBand = false,
  });

  final ApiClient client;
  final String path;
  final Object? version;
  final bool hideTryOnBand;

  @override
  Future<_ApiImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_ApiImage>(this);

  @override
  ImageStreamCompleter loadImage(_ApiImage key, ImageDecoderCallback decode) {
    return OneFrameImageStreamCompleter(_load(decode));
  }

  Future<ImageInfo> _load(ImageDecoderCallback decode) async {
    final bytes = await client.imageBytes(path);
    final codec = await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    try {
      final image = (await codec.getNextFrame()).image;
      return ImageInfo(
        image: hideTryOnBand ? await _withoutTryOnBand(image) : image,
      );
    } finally {
      codec.dispose();
    }
  }

  Future<ui.Image> _withoutTryOnBand(ui.Image image) async {
    // 着用画像の API が下端に描く帯の高さ (server/api/ai.py の label_ai)。
    final band = image.width ~/ 24;
    final height = image.height - (band < 14 ? 28 : band * 2);
    if (height <= 0) return image;

    final area = ui.Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      height.toDouble(),
    );
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(image, area, area, ui.Paint());
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(image.width, height);
    } finally {
      picture.dispose();
      image.dispose();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is _ApiImage &&
      identical(other.client, client) &&
      other.path == path &&
      other.version == version &&
      other.hideTryOnBand == hideTryOnBand;

  @override
  int get hashCode => Object.hash(client, path, version, hideTryOnBand);
}
