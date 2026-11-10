import 'package:flutter/material.dart';

import '../app/app_banner.dart';
import '../app/app_palette.dart';

import 'friend_outfit_items.dart';

class FriendOutfitPostBody extends StatefulWidget {
  const FriendOutfitPostBody({
    super.key,
    required this.image,
    required this.imageLabel,
    required this.items,
    required this.isGenerated,
    this.itemsPadding = EdgeInsets.zero,
    this.liked = false,
    this.onLike,
    this.onToggleSave,
    this.isSaved,
    this.onMatch,
  });

  final ImageProvider image;
  final String imageLabel;
  final List<FriendOutfitItem> items;
  final bool isGenerated;
  final EdgeInsets itemsPadding;
  final bool liked;
  final Future<void> Function(bool)? onLike;
  final Future<void> Function(int)? onToggleSave;
  final bool Function(int)? isSaved;
  final Future<void> Function(BuildContext, FriendOutfitItem)? onMatch;

  @override
  State<FriendOutfitPostBody> createState() => _FriendOutfitPostBodyState();
}

class _FriendOutfitPostBodyState extends State<FriendOutfitPostBody> {
  bool _liking = false;

  Future<void> _toggleLike() async {
    setState(() => _liking = true);
    try {
      await widget.onLike!(!widget.liked);
    } catch (_) {
      if (mounted) {
        showAppBanner(context, 'いいねを更新できませんでした', icon: Icons.error_outline);
      }
    } finally {
      if (mounted) setState(() => _liking = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 1,
          child: ColoredBox(
            color: context.palette.control,
            child: Image(
              image: widget.image,
              gaplessPlayback: true,
              fit: BoxFit.contain,
              semanticLabel: widget.imageLabel,
              errorBuilder: (_, _, _) =>
                  const Center(child: Text('画像を表示できませんでした')),
            ),
          ),
        ),
      ),
      if (widget.isGenerated)
        Padding(
          padding: const EdgeInsets.only(top: 4, right: 4),
          child: Text(
            'AI 生成',
            textAlign: TextAlign.end,
            style: TextStyle(fontSize: 12, color: context.palette.muted),
          ),
        ),
      if (widget.onLike != null)
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            tooltip: widget.liked ? 'いいねを取り消す' : 'いいね',
            onPressed: _liking ? null : _toggleLike,
            icon: Icon(widget.liked ? Icons.favorite : Icons.favorite_border),
          ),
        ),
      if (widget.items.isNotEmpty)
        Padding(
          padding: widget.itemsPadding,
          child: FriendOutfitItems(
            items: widget.items,
            outfitImage: widget.image,
            isGenerated: widget.isGenerated,
            onToggleSave: widget.onToggleSave,
            isSaved: widget.isSaved,
            onMatch: widget.onMatch,
            liked: widget.liked,
            onLike: widget.onLike,
          ),
        ),
    ],
  );
}
