import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/app_loading.dart';
import '../app/app_palette.dart';
import '../mypage/my_page_screen.dart';
import '../mypage/profile_photo.dart';

class ProfilePhotoCropScreen extends StatefulWidget {
  const ProfilePhotoCropScreen({
    super.key,
    required this.photo,
    required this.previewBuilder,
  });

  final ProfilePhoto photo;
  final Widget Function(ProfilePhoto, double topInset) previewBuilder;

  @override
  State<ProfilePhotoCropScreen> createState() => _ProfilePhotoCropScreenState();
}

class _ProfilePhotoCropScreenState extends State<ProfilePhotoCropScreen> {
  late ProfilePhoto _photo = widget.photo;
  ImageStream? _stream;
  Size? _imageSize;
  bool _failed = false;
  Offset _gestureAnchor = Offset.zero;
  double _gestureZoom = 1;

  late final _listener = ImageStreamListener(
    (info, _) {
      final size = Size(
        info.image.width.toDouble(),
        info.image.height.toDouble(),
      );
      info.dispose();
      if (mounted && _imageSize != size) setState(() => _imageSize = size);
    },
    onError: (_, _) {
      if (mounted) setState(() => _failed = true);
    },
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_stream != null) return;
    final stream = MemoryImage(widget.photo.bytes)
        .resolve(createLocalImageConfiguration(context));
    _stream = stream;
    stream.addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  Size _drawnSize(Size viewport, double zoom) {
    final size = _imageSize!;
    final cover = math.max(
      viewport.width / size.width,
      viewport.height / size.height,
    );
    return size * (cover * zoom);
  }

  Offset _imagePoint(Size viewport, Offset focalPoint) {
    final drawn = _drawnSize(viewport, _photo.zoom);
    final origin = _photo.alignment.inscribe(drawn, Offset.zero & viewport);
    final offset = focalPoint - origin.topLeft;
    return Offset(offset.dx / drawn.width, offset.dy / drawn.height);
  }

  void _movePhoto(
    Size viewport,
    Offset focalPoint,
    Offset anchor,
    double zoom,
  ) {
    final drawn = _drawnSize(viewport, zoom);
    final offset =
        focalPoint - Offset(anchor.dx * drawn.width, anchor.dy * drawn.height);

    // -1 は画像の先頭、+1 は末尾。画像の外側が枠に入らないようにする。
    double axis(double position, double overflow, double previous) =>
        overflow > 0.0001
        ? (-position / overflow * 2 - 1).clamp(-1.0, 1.0)
        : previous;

    setState(() {
      _photo = ProfilePhoto(
        _photo.bytes,
        alignment: Alignment(
          axis(offset.dx, drawn.width - viewport.width, _photo.alignment.x),
          axis(offset.dy, drawn.height - viewport.height, _photo.alignment.y),
        ),
        zoom: zoom,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.palette;
    final ready = _imageSize != null && !_failed;
    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(
        backgroundColor: colors.canvas,
        title: const Text('表示範囲を調整'),
        actions: [
          TextButton(
            onPressed: ready ? () => Navigator.pop(context, _photo) : null,
            child: const Text('適用'),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        left: false,
        right: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final topInset = MyPageHeader.previewTopInsetOf(context);
            final viewport = Size(
              constraints.maxWidth,
              MyPageHeader.expandedHeight + topInset,
            );
            return Column(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: _failed
                        ? const Center(child: Text('画像を表示できませんでした'))
                        : !ready
                        ? const Center(child: AppLoadingIndicator())
                        : FittedBox(
                            fit: BoxFit.scaleDown,
                            child: SizedBox.fromSize(
                              size: viewport,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onScaleStart: (details) {
                                  _gestureZoom = _photo.zoom;
                                  _gestureAnchor = _imagePoint(
                                    viewport,
                                    details.localFocalPoint,
                                  );
                                },
                                onScaleUpdate: (details) => _movePhoto(
                                  viewport,
                                  details.localFocalPoint,
                                  _gestureAnchor,
                                  (_gestureZoom * details.scale).clamp(
                                    1.0,
                                    ProfilePhoto.maxZoom,
                                  ),
                                ),
                                child: widget.previewBuilder(_photo, topInset),
                              ),
                            ),
                          ),
                  ),
                ),
                if (ready)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Column(
                      children: [
                        Text(
                          'ドラッグで移動、ピンチで拡大・縮小',
                          style: TextStyle(color: colors.muted),
                        ),
                        Row(
                          children: [
                            const Text('拡大'),
                            Expanded(
                              child: Slider(
                                value: _photo.zoom,
                                min: 1,
                                max: ProfilePhoto.maxZoom,
                                semanticFormatterCallback: (value) =>
                                    '${(value * 100).round()}%',
                                onChanged: (zoom) {
                                  final center = viewport.center(Offset.zero);
                                  _movePhoto(
                                    viewport,
                                    center,
                                    _imagePoint(viewport, center),
                                    zoom,
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
