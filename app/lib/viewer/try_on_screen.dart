import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/api_models.dart';
import '../app/app_banner.dart';
import '../app/app_loading.dart';
import '../app/app_palette.dart';
import '../app/confirmation_sheet.dart';
import '../capture/outfit_camera_screen.dart';
import '../common/outfit_item_tile.dart';

class TryOnScreen extends StatefulWidget {
  const TryOnScreen({
    super.key,
    required this.api,
    required this.cardId,
    required this.item,
    required this.wardrobeItemIds,
    required this.wardrobe,
  });

  final ApiClient api;
  final String cardId;
  final CardItem item;
  final List<String> wardrobeItemIds;
  final Future<Map<String, WardrobeItem>> wardrobe;

  @override
  State<TryOnScreen> createState() => _TryOnScreenState();
}

class _TryOnScreenState extends State<TryOnScreen> {
  static const _itemGap = 8.0;
  late var _result = _generate();
  bool _editingPhoto = false;

  Future<TryOnResult> _generate({bool regenerate = false}) => widget.api.tryOn(
    widget.cardId,
    widget.item.cardItemId,
    widget.wardrobeItemIds,
    regenerate: regenerate,
  );

  Future<void> _capture() async {
    if (_editingPhoto) return;
    setState(() => _editingPhoto = true);
    var saved = false;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => OutfitCameraScreen(
            confirmLabel: '全身写真を保存',
            allowDebugOutfitPhoto: false,
            onPhotoConfirmed: (photo) async {
              await widget.api.putTryOnPhoto(await photo.readAsBytes());
              saved = true;
            },
          ),
        ),
      );
      if (mounted && saved) {
        setState(() {
          _result = _generate(regenerate: true);
        });
      }
    } finally {
      if (mounted) setState(() => _editingPhoto = false);
    }
  }

  Widget _usedItems(AppPalette colors, double tileWidth) =>
      FutureBuilder<Map<String, WardrobeItem>>(
        future: widget.wardrobe,
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <String, WardrobeItem>{};
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '着用アイテム',
                style: TextStyle(
                  color: colors.ink,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  spacing: _itemGap,
                  children: [
                    SizedBox(
                      width: tileWidth,
                      child: OutfitItemTile(
                        label: widget.item.label,
                        image: widget.api.image(widget.item.image),
                      ),
                    ),
                    for (final id in widget.wardrobeItemIds)
                      SizedBox(
                        width: tileWidth,
                        child: OutfitItemTile(
                          label: items[id]?.label ?? '手持ちの服',
                          image: widget.api.image(
                            items[id]?.image ??
                                '/v1/wardrobe/${Uri.encodeComponent(id)}/image',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      );

  Widget _resultPanel(AppPalette colors, Widget child) => DecoratedBox(
    decoration: BoxDecoration(
      color: colors.panel,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: colors.outline),
    ),
    child: Padding(padding: const EdgeInsets.all(14), child: child),
  );

  Widget _retryButton(AppPalette colors, {required bool regenerate}) =>
      OutlinedButton(
        onPressed: _editingPhoto
            ? null
            : () => setState(() {
                _result = _generate(regenerate: regenerate);
              }),
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.ink,
          side: BorderSide(color: colors.outline),
          minimumSize: const Size(0, 48),
          shape: appActionShape,
        ),
        child: Text(regenerate ? 'やり直す' : 'もう一度'),
      );

  Widget _resultView(TryOnResult result, AppPalette colors) => LayoutBuilder(
    builder: (context, constraints) {
      const padding = EdgeInsets.fromLTRB(16, 8, 16, 12);
      final minHeight = 190 + 4 * MediaQuery.textScalerOf(context).scale(14);
      final height = math.max(constraints.maxHeight, minHeight);
      // 4 点ある時は 4 点目を少し見せ、横に続くことを伝える。
      final visibleItems = math.min(widget.wardrobeItemIds.length + 1.0, 3.5);
      final tileWidth = math
          .min(
            height * 0.19,
            (constraints.maxWidth -
                    padding.horizontal -
                    _itemGap * (visibleItems - 1)) /
                visibleItems,
          )
          .clamp(0.0, 104.0);
      final content = SizedBox(
        height: height,
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _resultPanel(
                  colors,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image(
                            image: widget.api.tryOnImage(result.image),
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) =>
                                const Center(child: Text('画像を読み込めませんでした')),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        result.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.muted),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _usedItems(colors, tileWidth),
              const SizedBox(height: 12),
              _retryButton(colors, regenerate: true),
            ],
          ),
        ),
      );
      // 極端に低い表示領域でも、文字サイズを縮めず操作できるようにする。
      return constraints.maxHeight < minHeight
          ? SingleChildScrollView(child: content)
          : content;
    },
  );

  Future<void> _deletePhoto() async {
    final confirm = await showConfirmationSheet(
      context,
      title: '着用イメージ用の全身写真を削除しますか？',
      icon: Icons.delete_outline,
      confirmLabel: '削除',
    );
    if (!mounted || confirm != true || _editingPhoto) return;
    setState(() => _editingPhoto = true);
    try {
      await widget.api.deleteTryOnPhoto();
      if (mounted) {
        showAppBanner(context, '全身写真を削除しました', icon: Icons.check_circle_outline);
      }
    } catch (_) {
      if (mounted) {
        showAppBanner(context, '全身写真を削除できませんでした', icon: Icons.error_outline);
      }
    } finally {
      if (mounted) setState(() => _editingPhoto = false);
    }
  }

  Future<void> _openPhotoMenu({required bool expired}) async {
    final capture = await showActionSheet<bool>(
      context,
      title: '全身写真の設定',
      icon: Icons.photo_camera_outlined,
      actions: [
        if (!expired) (value: true, label: '全身写真を撮る', destructive: false),
        (value: false, label: '全身写真を削除', destructive: true),
        (value: null, label: 'キャンセル', destructive: false),
      ],
    );
    if (!mounted || capture == null) return;
    if (capture) {
      await _capture();
    } else {
      await _deletePhoto();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<TryOnResult>(
    future: _result,
    builder: (context, snapshot) {
      final loading = snapshot.connectionState != ConnectionState.done;
      final result = snapshot.data;
      final error = snapshot.error;
      final expired = error is ApiException && error.statusCode == 410;
      final colors = context.palette;
      return Scaffold(
        backgroundColor: colors.canvas,
        appBar: AppBar(
          backgroundColor: colors.canvas,
          foregroundColor: colors.ink,
          surfaceTintColor: Colors.transparent,
          title: const Text(
            '着用イメージ',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              tooltip: '全身写真の設定',
              icon: const Icon(Icons.more_vert),
              onPressed: loading || _editingPhoto
                  ? null
                  : () => _openPhotoMenu(expired: expired),
            ),
          ],
        ),
        body: loading
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppLoadingIndicator(size: 32),
                    const SizedBox(height: 12),
                    Text(
                      '着用イメージを作っています',
                      style: TextStyle(color: colors.muted),
                    ),
                  ],
                ),
              )
            : SafeArea(
                top: false,
                child: result != null
                    ? _resultView(result, colors)
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        children: [
                          _resultPanel(
                            colors,
                            Text(
                              error is ApiException
                                  ? error.message
                                  : '着用イメージを作れませんでした',
                              style: TextStyle(
                                color: colors.ink,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (error is ApiException &&
                              error.code == 'photo_required')
                            FilledButton.icon(
                              onPressed: _editingPhoto ? null : _capture,
                              icon: const Icon(Icons.photo_camera_outlined),
                              label: const Text('全身写真を撮る'),
                              style: FilledButton.styleFrom(
                                backgroundColor: colors.ink,
                                foregroundColor: colors.canvas,
                                minimumSize: const Size(0, 48),
                                shape: appActionShape,
                              ),
                            )
                          else if (!expired)
                            _retryButton(colors, regenerate: false),
                        ],
                      ),
              ),
      );
    },
  );
}
