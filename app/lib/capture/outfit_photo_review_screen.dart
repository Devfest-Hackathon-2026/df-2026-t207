import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app/app_palette.dart';
import 'outfit_review_background.dart';

/// 自分が撮影した写真を送信前に確認する画面。
class OutfitPhotoReviewScreen extends StatelessWidget {
  const OutfitPhotoReviewScreen({
    super.key,
    required this.photoBytes,
    required this.onRetake,
    required this.onConfirm,
    this.confirmLabel = '投稿',
    this.isDemo = false,
  });

  final Uint8List photoBytes;
  final VoidCallback? onRetake;
  final VoidCallback? onConfirm;
  final String confirmLabel;
  final bool isDemo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff242424),
      body: Stack(
        fit: StackFit.expand,
        children: [
          OutfitReviewBackground(photoBytes: photoBytes),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      tooltip: '戻る',
                      color: Colors.white,
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back),
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: FilledButton(
                            onPressed: onConfirm,
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xff222222),
                            ),
                            child: Text(
                              confirmLabel,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: IconButton.filled(
                          tooltip: '撮りなおす',
                          onPressed: onRetake,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xff222222),
                            shape: appActionShape,
                          ),
                          icon: const Icon(Icons.refresh),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
