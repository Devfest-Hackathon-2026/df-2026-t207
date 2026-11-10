import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

class ProfilePhoto {
  const ProfilePhoto(
    this.bytes, {
    this.alignment = Alignment.topCenter,
    this.zoom = 1,
  });

  static const maxZoom = 4.0;

  final Uint8List bytes;
  final Alignment alignment;
  final double zoom;

  String encodeCrop() =>
      jsonEncode({'x': alignment.x, 'y': alignment.y, 'scale': zoom});

  factory ProfilePhoto.fromRemote(Uint8List bytes, String? crop) {
    final (alignment, zoom) = parseProfileCrop(crop);
    return ProfilePhoto(bytes, alignment: alignment, zoom: zoom);
  }

  String encode() => jsonEncode({
    'bytes': base64Encode(bytes),
    'x': alignment.x,
    'y': alignment.y,
    'zoom': zoom,
  });

  factory ProfilePhoto.decode(String value) {
    // 以前の Web 版で保存した画像には切り取りの設定がない。
    if (!value.startsWith('{')) return ProfilePhoto(base64Decode(value));
    final data = jsonDecode(value) as Map<String, dynamic>;
    return ProfilePhoto(
      base64Decode(data['bytes'] as String),
      alignment: Alignment(
        (data['x'] as num).toDouble().clamp(-1.0, 1.0),
        (data['y'] as num).toDouble().clamp(-1.0, 1.0),
      ),
      zoom: (data['zoom'] as num).toDouble().clamp(1.0, maxZoom),
    );
  }
}

(Alignment, double) parseProfileCrop(String? crop) {
  if (crop != null) {
    try {
      final data = jsonDecode(crop) as Map<String, dynamic>;
      double number(String key, double fallback) =>
          (data[key] as num?)?.toDouble() ?? fallback;
      return (
        Alignment(number('x', 0).clamp(-1, 1), number('y', -1).clamp(-1, 1)),
        number('scale', 1).clamp(1, ProfilePhoto.maxZoom),
      );
    } catch (_) {
      // 古い、または読み取れない表示範囲は既定の位置で描く。
    }
  }
  return (Alignment.topCenter, 1.0);
}

/// ヘッダーと設定のプレビューで、同じ位置と拡大率を使う。
class ProfilePhotoImage extends StatelessWidget {
  const ProfilePhotoImage({super.key, required this.photo});

  final ProfilePhoto photo;

  @override
  Widget build(BuildContext context) => CroppedProfileImage(
    image: MemoryImage(photo.bytes),
    alignment: photo.alignment,
    zoom: photo.zoom,
  );
}

class CroppedProfileImage extends StatelessWidget {
  const CroppedProfileImage({
    super.key,
    required this.image,
    required this.alignment,
    required this.zoom,
  });

  factory CroppedProfileImage.remote(ImageProvider image, String? crop) {
    final (alignment, zoom) = parseProfileCrop(crop);
    return CroppedProfileImage(image: image, alignment: alignment, zoom: zoom);
  }

  final ImageProvider image;
  final Alignment alignment;
  final double zoom;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth * zoom;
      final height = constraints.maxHeight * zoom;
      return ClipRect(
        child: OverflowBox(
          alignment: alignment,
          minWidth: width,
          maxWidth: width,
          minHeight: height,
          maxHeight: height,
          child: Image(
            image: image,
            gaplessPlayback: true,
            fit: BoxFit.cover,
            alignment: alignment,
            errorBuilder: (_, _, _) =>
                const ColoredBox(color: Color(0xff3a3a36)),
          ),
        ),
      );
    },
  );
}
