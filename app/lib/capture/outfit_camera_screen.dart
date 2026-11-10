import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api/api_models.dart';
import '../app/app_banner.dart';
import '../app/app_loading.dart';
import '../app/app_palette.dart';

import 'outfit_photo_review_screen.dart';

/// 撮影から写真の確認までを、1 つのルートで扱う。
class OutfitCameraScreen extends StatefulWidget {
  const OutfitCameraScreen({
    super.key,
    this.onPhotoConfirmed,
    this.confirmLabel = '投稿',
    this.allowDebugOutfitPhoto = true,
  });

  final Future<void> Function(XFile photo)? onPhotoConfirmed;
  final String confirmLabel;
  final bool allowDebugOutfitPhoto;

  @override
  State<OutfitCameraScreen> createState() => _OutfitCameraScreenState();
}

class _OutfitCameraScreenState extends State<OutfitCameraScreen>
    with WidgetsBindingObserver {
  static const _debugPhotoPath = String.fromEnvironment(
    'OUTFIT_TEST_PHOTO_PATH',
  );
  CameraController? _controller;
  CameraDescription? _selectedCamera;
  List<CameraDescription> _cameras = const [];
  Future<void> _cameraOperation = Future<void>.value();
  ({XFile file, Uint8List bytes})? _review;
  int _generation = 0;
  bool _loading = true;
  bool _takingPhoto = false;
  bool _posting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _openCamera();
  }

  CameraDescription? get _alternateCamera {
    final direction = switch (_selectedCamera?.lensDirection) {
      CameraLensDirection.back => CameraLensDirection.front,
      CameraLensDirection.front => CameraLensDirection.back,
      _ => null,
    };
    if (direction == null) return null;
    return _cameras
        .where((camera) => camera.lensDirection == direction)
        .firstOrNull;
  }

  void _openCamera({CameraDescription? target}) {
    final generation = ++_generation;
    _closeCamera();
    setState(() {
      _loading = true;
      _error = null;
    });
    // 切り替え中に画面を離れても、古いカメラを解放してから次を開く。
    _cameraOperation = _cameraOperation.then(
      (_) => _initializeCamera(generation, target),
    );
  }

  bool _isCurrent(int generation) => mounted && generation == _generation;

  Future<void> _initializeCamera(
    int generation,
    CameraDescription? target,
  ) async {
    if (!_isCurrent(generation)) return;
    try {
      final cameras = await availableCameras();
      if (!_isCurrent(generation)) return;
      if (cameras.isEmpty) throw StateError('No camera available');
      final previous =
          cameras.where((camera) => camera == _selectedCamera).firstOrNull ??
          cameras
              .where((c) => c.lensDirection == CameraLensDirection.back)
              .firstOrNull ??
          cameras.first;
      final requested = cameras.contains(target) ? target! : previous;
      var switchFailed = target != null && requested != target;
      CameraController controller;
      try {
        controller = await _createController(requested);
      } catch (_) {
        if (requested == previous || !_isCurrent(generation)) rethrow;
        controller = await _createController(previous);
        switchFailed = true;
      }
      if (!mounted || generation != _generation) {
        await _disposeController(controller);
        return;
      }
      setState(() {
        _controller = controller;
        _selectedCamera = controller.description;
        _cameras = cameras;
        _loading = false;
      });
      if (switchFailed) {
        showAppBanner(context, 'カメラを切り替えられませんでした', icon: Icons.error_outline);
      }
    } catch (_) {
      if (_isCurrent(generation)) {
        setState(() {
          _loading = false;
          _error = 'カメラを利用できません。権限と設定を確認してください';
        });
      }
    }
  }

  Future<CameraController> _createController(CameraDescription camera) async {
    final controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
    );
    try {
      await controller.initialize();
      return controller;
    } catch (_) {
      await _disposeController(controller);
      rethrow;
    }
  }

  Future<void> _disposeController(CameraController controller) async {
    try {
      await controller.dispose();
    } catch (_) {
      // 解放に失敗しても、次の初期化や再試行を止めない。
    }
  }

  void _switchCamera() {
    final target = _alternateCamera;
    if (target == null || _controller == null || _loading || _takingPhoto) {
      return;
    }
    _openCamera(target: target);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_review != null) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _generation++;
      _closeCamera();
      if (mounted) setState(() => _loading = true);
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      _openCamera();
    }
  }

  void _closeCamera() {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      _cameraOperation = _cameraOperation.then(
        (_) => _disposeController(controller),
      );
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _takingPhoto) {
      return;
    }
    setState(() => _takingPhoto = true);
    try {
      final photo =
          kDebugMode &&
              !kIsWeb &&
              defaultTargetPlatform == TargetPlatform.android &&
              widget.allowDebugOutfitPhoto &&
              _debugPhotoPath.isNotEmpty
          ? XFile(_debugPhotoPath)
          : await controller.takePicture();
      final bytes = await photo.readAsBytes();
      if (!mounted || _controller != controller) return;
      _closeCamera();
      setState(() => _review = (file: photo, bytes: bytes));
    } catch (_) {
      if (mounted && _controller == controller) {
        showAppBanner(
          context,
          '撮影できませんでした。もう一度お試しください',
          icon: Icons.error_outline,
        );
      }
    } finally {
      if (mounted) setState(() => _takingPhoto = false);
    }
  }

  Future<void> _post(XFile photo) async {
    final confirm = widget.onPhotoConfirmed;
    if (confirm == null) {
      showAppBanner(context, '投稿はまだ利用できません');
      return;
    }
    if (_posting) return;
    setState(() => _posting = true);
    try {
      await confirm(photo);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        final message = error is ApiException
            ? error.message
            : '送信できませんでした。もう一度お試しください';
        showAppBanner(context, message, icon: Icons.error_outline);
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    _closeCamera();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final review = _review;
    if (review != null) {
      return PopScope(
        canPop: !_posting,
        child: OutfitPhotoReviewScreen(
          photoBytes: review.bytes,
          confirmLabel: widget.confirmLabel,
          onConfirm: _posting ? null : () => _post(review.file),
          onRetake: _posting
              ? null
              : () {
                  _review = null;
                  _openCamera();
                },
        ),
      );
    }
    final controller = _controller;
    final alternate = _alternateCamera;
    final loading = _loading && !(controller?.value.isInitialized ?? false);
    final colors = context.palette;
    final controls = loading ? colors.ink : Colors.white;
    return Scaffold(
      backgroundColor: loading ? colors.loadingBackground : Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (controller != null && controller.value.isInitialized)
            Center(child: CameraPreview(controller))
          else if (loading)
            const Center(child: AppLoadingIndicator())
          else
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error ?? 'カメラを利用できません',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _openCamera,
                      child: const Text('もう一度試す'),
                    ),
                  ],
                ),
              ),
            ),
          SafeArea(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      tooltip: '戻る',
                      color: controls,
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    if (alternate != null && (controller != null || loading))
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: IconButton.filled(
                          tooltip:
                              alternate.lensDirection ==
                                  CameraLensDirection.front
                              ? '前面カメラに切り替え'
                              : '背面カメラに切り替え',
                          onPressed: controller != null && !_takingPhoto
                              ? _switchCamera
                              : null,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black54,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.black26,
                            disabledForegroundColor: Colors.white54,
                          ),
                          icon: const Icon(Icons.cameraswitch_outlined),
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Semantics(
                    button: true,
                    label: '写真を撮る',
                    child: InkResponse(
                      onTap: controller != null && !_takingPhoto
                          ? _capture
                          : null,
                      radius: 40,
                      child: Container(
                        width: 72,
                        height: 72,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: controls, width: 3),
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _takingPhoto
                                ? controls.withValues(alpha: 0.54)
                                : controls,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
