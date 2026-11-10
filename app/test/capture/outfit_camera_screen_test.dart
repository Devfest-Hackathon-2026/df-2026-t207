import 'dart:async';

import 'package:app/capture/outfit_camera_screen.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _back = CameraDescription(
  name: 'back',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 90,
);
const _front = CameraDescription(
  name: 'front',
  lensDirection: CameraLensDirection.front,
  sensorOrientation: 270,
);

void main() {
  testWidgets('切り替えに失敗しても元のカメラで再試行できる', (tester) async {
    final platform = _CameraPlatform([_front, _back])..failFront = true;
    await _showCamera(tester, platform);

    expect(platform.active, _back);
    await tester.tap(find.byTooltip('前面カメラに切り替え'));
    await tester.pumpAndSettle();

    expect(find.text('カメラを切り替えられませんでした'), findsOneWidget);
    expect(platform.active, _back);

    platform.failFront = false;
    await tester.tap(find.byTooltip('前面カメラに切り替え'));
    await tester.pumpAndSettle();
    expect(platform.active, _front);
    expect(find.byTooltip('背面カメラに切り替え'), findsOneWidget);
  });

  testWidgets('カメラが一方向だけの端末でもプレビューを開ける', (tester) async {
    final platform = _CameraPlatform([_front]);
    await _showCamera(tester, platform);

    expect(platform.active, _front);
    expect(find.byIcon(Icons.cameraswitch_outlined), findsNothing);
  });
}

Future<void> _showCamera(WidgetTester tester, _CameraPlatform platform) async {
  final original = CameraPlatform.instance;
  CameraPlatform.instance = platform;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    CameraPlatform.instance = original;
  });
  await tester.pumpWidget(const MaterialApp(home: OutfitCameraScreen()));
  await tester.pumpAndSettle();
}

class _CameraPlatform extends CameraPlatform {
  _CameraPlatform(this.cameras);

  final List<CameraDescription> cameras;
  CameraDescription? active;
  bool failFront = false;

  @override
  Future<List<CameraDescription>> availableCameras() async => cameras;

  @override
  Future<int> createCameraWithSettings(
    CameraDescription cameraDescription,
    MediaSettings mediaSettings,
  ) async {
    if (active != null) throw StateError('Camera is already open');
    active = cameraDescription;
    return cameras.indexOf(cameraDescription);
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    if (failFront && active == _front) {
      throw CameraException('Unavailable', 'Front camera could not start');
    }
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(
        CameraInitializedEvent(
          cameraId,
          1080,
          1920,
          ExposureMode.auto,
          false,
          FocusMode.auto,
          false,
        ),
      );

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      Stream.fromFuture(Completer<CameraErrorEvent>().future);

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();

  @override
  Widget buildPreview(int cameraId) => const SizedBox.expand();

  @override
  Future<void> dispose(int cameraId) async => active = null;
}
