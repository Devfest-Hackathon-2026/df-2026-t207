import 'package:flutter/material.dart';

import '../app/app_palette.dart';

/// API の `slot` (outer / top / bottom / shoes) を画面の言葉にする。
String slotLabel(String slot) {
  switch (slot) {
    case 'outer':
      return 'アウター';
    case 'top':
      return 'トップス';
    case 'bottom':
      return 'ボトムス';
    case 'dress':
      return 'ワンピース';
    case 'shoes':
      return 'シューズ';
    case 'bag':
      return 'バッグ';
    case 'accessory':
      return '小物';
    default:
      return 'その他';
  }
}

/// 並べる順。外側から足元へ。
int slotOrder(String slot) {
  const order = [
    'outer',
    'dress',
    'top',
    'bottom',
    'shoes',
    'bag',
    'accessory',
  ];
  final i = order.indexOf(slot);
  return i < 0 ? order.length : i;
}

/// 服の切り抜き 1 つと区分の名前を出す小さなタイル。
class OutfitItemTile extends StatelessWidget {
  const OutfitItemTile({
    super.key,
    required this.label,
    this.image,
    this.onTap,
    this.gaplessPlayback = false,
  });

  final String label;
  final ImageProvider? image;
  final VoidCallback? onTap;
  final bool gaplessPlayback;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.palette.control,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: image == null
                      ? Icon(
                          Icons.checkroom_outlined,
                          color: context.palette.muted,
                        )
                      : Padding(
                          padding: const EdgeInsets.all(6),
                          child: Image(
                            image: image!,
                            gaplessPlayback: gaplessPlayback,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => Icon(
                              Icons.checkroom_outlined,
                              color: context.palette.muted,
                            ),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            ExcludeSemantics(
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: context.palette.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
