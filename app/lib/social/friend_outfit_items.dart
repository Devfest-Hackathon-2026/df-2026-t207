import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_models.dart';
import '../app/app_banner.dart';
import '../app/app_palette.dart';
import '../common/outfit_item_tile.dart';
import '../viewer/nearby_outfits_screen.dart';

class FriendOutfitItem {
  const FriendOutfitItem({
    required this.slot,
    required this.label,
    this.color = '',
    this.index,
    this.memo = '',
    this.image,
  });

  final String slot;
  final String label;
  final String color;
  final int? index;
  final String memo;
  final ImageProvider? image;
}

class FriendOutfitItems extends StatefulWidget {
  const FriendOutfitItems({
    super.key,
    required this.items,
    required this.outfitImage,
    this.isGenerated = false,
    this.onToggleSave,
    this.isSaved,
    this.onMatch,
    this.liked = false,
    this.onLike,
  });

  final List<FriendOutfitItem> items;
  final ImageProvider outfitImage;
  final bool isGenerated;
  final Future<void> Function(int)? onToggleSave;
  final bool Function(int)? isSaved;
  final Future<void> Function(BuildContext, FriendOutfitItem)? onMatch;
  final bool liked;
  final Future<void> Function(bool)? onLike;

  @override
  State<FriendOutfitItems> createState() => _FriendOutfitItemsState();
}

class _FriendOutfitItemsState extends State<FriendOutfitItems> {
  bool _opening = false;
  List<FriendOutfitItem> get items => widget.items;
  ImageProvider get outfitImage => widget.outfitImage;
  bool get isGenerated => widget.isGenerated;
  Future<void> Function(int)? get onToggleSave => widget.onToggleSave;
  bool Function(int)? get isSaved => widget.isSaved;
  Future<void> Function(BuildContext, FriendOutfitItem)? get onMatch =>
      widget.onMatch;
  bool get liked => widget.liked;
  Future<void> Function(bool)? get onLike => widget.onLike;

  Future<void> _openDetails(
    BuildContext context,
    List<FriendOutfitItem> sorted,
    int selectedIndex,
  ) async {
    if (_opening) return;
    _opening = true;
    const channel = MethodChannel('jp.dfhack26.app/viewer_security');
    final secure = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    var enabled = false;
    try {
      if (secure) {
        try {
          await channel.invokeMethod<void>('enable');
          enabled = true;
        } catch (_) {
          if (context.mounted) {
            showAppBanner(context, 'コーデを開けませんでした', icon: Icons.error_outline);
          }
          return;
        }
      }
      if (!context.mounted) return;
      const cardId = 'friend_detail';
      const outfitPath = 'friend_outfit';
      final card = NearbyCard(
        cardId: cardId,
        image: outfitPath,
        seenAgoSec: 0,
        expiresAt: DateTime.now().add(const Duration(minutes: 30)),
        isDemo: isGenerated,
        items: [
          for (final (index, item) in sorted.indexed)
            CardItem(
              cardItemId: '$index',
              slot: item.slot,
              label: item.label,
              color: item.color,
              memo: item.memo,
              image: 'friend_item_$index',
            ),
        ],
      );
      FriendOutfitItem itemFor(CardItem item) =>
          sorted[int.parse(item.cardItemId)];
      Future<void> toggleSaved(String id) async {
        final index = sorted[int.parse(id)].index;
        if (index != null) await onToggleSave!(index);
      }

      final route = MaterialPageRoute<void>(
        builder: (detailContext) => NearbyOutfitsScreen(
          loadNearby: () async =>
              NearbyResult(cards: [card], viewerPublishing: true),
          imageFor: (path) => path == outfitPath
              ? outfitImage
              : sorted[int.parse(path.substring('friend_item_'.length))].image,
          initialDetails: true,
          initialItemId: '$selectedIndex',
          initialLiked: liked,
          initialSavedItemIds: {
            for (final (index, item) in sorted.indexed)
              if (item.index != null && (isSaved?.call(item.index!) ?? false))
                '$index',
          },
          canMatchItem: (item) => itemFor(item).index != null,
          canSaveItem: (item) => itemFor(item).index != null,
          showLike: onLike != null,
          showSave: onToggleSave != null,
          onSetLike: onLike == null ? null : (_, value) => onLike!(value),
          onSaveItem: onToggleSave == null
              ? null
              : (_, id) async {
                  await toggleSaved(id);
                  return id;
                },
          onDeleteSave: onToggleSave == null ? null : toggleSaved,
          onMatch: onMatch == null
              ? null
              : (_, item) => onMatch!(detailContext, itemFor(item)),
        ),
      );
      await Navigator.of(context, rootNavigator: true).push<void>(route);
      await route.completed;
    } finally {
      try {
        if (enabled) await channel.invokeMethod<void>('disable');
      } finally {
        _opening = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final sorted = [...items]
      ..sort((a, b) => slotOrder(a.slot).compareTo(slotOrder(b.slot)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextButton(
          onPressed: () => _openDetails(context, sorted, 0),
          style: TextButton.styleFrom(
            foregroundColor: context.palette.ink,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text('着用アイテム')),
              Icon(Icons.chevron_right, size: 20),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final tileWidth = ((constraints.maxWidth - 24) / 4).clamp(
              48.0,
              96.0,
            );
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (index, item) in sorted.indexed) ...[
                    if (index > 0) const SizedBox(width: 8),
                    SizedBox(
                      key: ValueKey((index, item.index, item.slot, item.label)),
                      width: tileWidth,
                      child: OutfitItemTile(
                        label: slotLabel(item.slot),
                        image: item.image,
                        gaplessPlayback: true,
                        onTap: () => _openDetails(context, sorted, index),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
