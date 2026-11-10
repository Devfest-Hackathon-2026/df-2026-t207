import 'dart:convert';
import 'dart:io';

import 'package:app/mypage/my_page_screen.dart';
import 'package:app/mypage/profile_photo.dart';
import 'package:app/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('保存済みの画像をマイページと同じ大きさで調整して保存できる', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final bytes = File('assets/images/login_illustration.png')
        .readAsBytesSync();
    final legacyPhoto = ProfilePhoto.decode(base64Encode(bytes));
    expect(legacyPhoto.alignment, Alignment.topCenter);
    ProfilePhoto? saved;

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          displayName: 'りお',
          photo: legacyPhoto,
          isPublishing: false,
          onSaveName: (_) async {},
          onSavePhoto: (photo) async {
            saved = ProfilePhoto.decode(photo!.encode());
          },
          onLogout: () async {},
          onDarkModeChanged: (_) async {},
        ),
      ),
    );
    await tester.runAsync(
      () => precacheImage(
        MemoryImage(legacyPhoto.bytes),
        tester.element(find.byType(SettingsScreen)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('この画像をフレンドに表示'), findsNothing);
    final header = find.byType(MyPageHeader);
    final expectedSize = Size(390, MyPageHeader.expandedHeight);
    expect(tester.getSize(header), expectedSize);
    await tester.tap(find.text('表示範囲を調整'));
    await tester.pumpAndSettle();
    expect(tester.getSize(header), expectedSize);
    await tester.dragFrom(tester.getRect(header).center, const Offset(0, -100));
    await tester.pump();
    final moved = tester.widget<ProfilePhotoImage>(
      find.byType(ProfilePhotoImage),
    );
    expect(moved.photo.alignment.y, greaterThan(-1));
    await tester.tapAt(tester.getCenter(find.byType(Slider)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('適用'));
    await tester.pumpAndSettle();

    expect(saved?.zoom, greaterThan(1));
    expect(saved?.bytes, bytes);
    final preview = tester.widget<ProfilePhotoImage>(
      find.byType(ProfilePhotoImage),
    );
    expect(preview.photo.zoom, saved?.zoom);
    expect(preview.photo.alignment, saved?.alignment);
  });
}
