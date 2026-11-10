import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../app/app_banner.dart';
import '../app/app_palette.dart';
import '../capture/outfit_items_review_screen.dart';
import '../capture/outfit_review_background.dart';
import '../common/outfit_capture_prompt.dart';
import '../common/outfit_item_tile.dart';
import '../social/friend_outfit_items.dart' show FriendOutfitItem;
import '../social/friend_avatar.dart';
import '../social/friend_outfit_post_body.dart';

/// ホームに出す、今日の着用アイテム 1 つ分。
class HomeOutfitItem {
  const HomeOutfitItem({
    required this.slot,
    required this.label,
    this.image,
    this.id,
    this.memo = '',
  });

  /// API の `slot` (outer / top / bottom / shoes)。
  final String slot;
  final String label;
  final ImageProvider? image;
  final String? id;
  final String memo;
}

/// ホームに出すフレンドの投稿 1 件分。
class HomeFriendPost {
  const HomeFriendPost({
    required this.displayName,
    required this.timeLabel,
    required this.image,
    this.key,
    this.isGenerated = false,
    this.items = const [],
    this.profileImage,
    this.profileCrop,
    this.onOpenProfile,
    this.liked = false,
    this.onLike,
    this.onToggleSave,
    this.isSaved,
    this.onMatch,
  });

  final String displayName;
  final String timeLabel;
  final ImageProvider image;
  final Key? key;
  final bool isGenerated;
  final List<FriendOutfitItem> items;
  final ImageProvider? profileImage;
  final String? profileCrop;
  final VoidCallback? onOpenProfile;
  final bool liked;
  final Future<void> Function(bool)? onLike;
  final Future<void> Function(int)? onToggleSave;
  final bool Function(int)? isSaved;
  final Future<void> Function(BuildContext, FriendOutfitItem)? onMatch;
}

/// ホーム (仕様書の S3)。今日のコーデとフレンドの投稿。
///
/// 見られた回数は数だけを出し、誰が見たかは出さない。
/// データの取得と画面の行き来は呼び出し側で行う。
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.hasTodayOutfit,
    required this.isPublishing,
    required this.viewCountToday,
    required this.items,
    required this.onCapturePressed,
    required this.onPublishPressed,
    this.onItemsPressed,
    this.onEditOutfit,
    this.loadClosetItems,
    this.allowLocalOutfitEdits = false,
    this.onNotificationsPressed,
    this.hasUnreadNotifications = false,
    this.todayOutfitImage,
    this.friendPosts = const [],
    this.bottomPadding = 104,
  });

  /// 今日のコーデを登録済みか。
  final bool hasTodayOutfit;

  /// 頭と背景を消した、自分の今日の着姿。
  final ImageProvider? todayOutfitImage;
  final List<HomeFriendPost> friendPosts;

  final bool isPublishing;
  final int viewCountToday;
  final List<HomeOutfitItem> items;

  final VoidCallback onCapturePressed;
  final VoidCallback? onItemsPressed;
  final void Function(BuildContext, int?, Object?)? onEditOutfit;
  final Future<List<HomeOutfitItem>> Function()? loadClosetItems;
  final bool allowLocalOutfitEdits;
  final VoidCallback onPublishPressed;
  final VoidCallback? onNotificationsPressed;
  final bool hasUnreadNotifications;

  /// 下に重なるメニューの分の余白。
  final double bottomPadding;

  static const _sectionMargin = 8.0;
  static const _headerActionWidth = 48.0;

  @override
  Widget build(BuildContext context) {
    final sorted = [...items]
      ..sort((a, b) => slotOrder(a.slot).compareTo(slotOrder(b.slot)));
    return Scaffold(
      backgroundColor: context.palette.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: context.palette.panel,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(20),
                            ),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(10),
                            child: Text('今日のコーデ', style: _Section.titleStyle),
                          ),
                        ),
                      ),
                    ),
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: hasTodayOutfit
                          ? _TodayOutfitHeader(
                              width: constraints.maxWidth,
                              image: todayOutfitImage,
                              viewCount: viewCountToday,
                              isPublishing: isPublishing,
                              onPublishPressed: onPublishPressed,
                            )
                          : _UnpostedOutfitHeader(
                              width: constraints.maxWidth,
                              onCapturePressed: onCapturePressed,
                            ),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        _sectionMargin,
                        12,
                        _sectionMargin,
                        bottomPadding,
                      ),
                      sliver: SliverList.list(
                        children: [
                          if (hasTodayOutfit &&
                              (sorted.isNotEmpty || onEditOutfit != null)) ...[
                            _buildItems(
                              context,
                              sorted,
                              constraints.maxWidth - 2 * _sectionMargin,
                            ),
                            const SizedBox(height: 16),
                          ],
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                            child: Semantics(
                              header: true,
                              child: const Text(
                                'フレンドの投稿',
                                style: TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          if (friendPosts.isEmpty)
                            const Padding(
                              padding: EdgeInsets.fromLTRB(4, 4, 4, 10),
                              child: Text('フレンドの投稿はまだありません'),
                            ),
                          for (final post in friendPosts)
                            Padding(
                              key: post.key,
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _FriendPostCard(post: post),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
    child: Row(
      children: [
        const SizedBox(width: _headerActionWidth),
        Expanded(
          child: Semantics(
            header: true,
            label: 'Wearby',
            child: Center(
              child: Image.asset(
                'assets/images/wearby_wordmark.png',
                height: 22,
                color: context.palette.ink,
                excludeFromSemantics: true,
              ),
            ),
          ),
        ),
        SizedBox(
          width: _headerActionWidth,
          child: IconButton(
            tooltip: '通知',
            onPressed:
                onNotificationsPressed ??
                () {
                  showAppBanner(context, '通知はまだ利用できません');
                },
            style: IconButton.styleFrom(
              backgroundColor: context.palette.control,
              foregroundColor: context.palette.ink,
              side: BorderSide(color: context.palette.outline),
            ),
            icon: Badge(
              isLabelVisible: hasUnreadNotifications,
              backgroundColor: context.palette.muted,
              smallSize: 8,
              child: const Icon(Icons.notifications_none_outlined),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildItems(
    BuildContext context,
    List<HomeOutfitItem> sorted,
    double sectionWidth,
  ) {
    const gap = 8.0;
    final scrollable = sorted.length >= 4;
    // 4 枚目を少し見切れさせて、横に続くことを示す。
    final visibleTiles = scrollable ? 3.75 : 4;
    final tileWidth =
        (sectionWidth - 2 * _Section.horizontalPadding - gap * 3) /
        visibleTiles;
    Widget tile(int index) => SizedBox(
      width: tileWidth,
      child: OutfitItemTile(
        label: slotLabel(sorted[index].slot),
        image: sorted[index].image,
        onTap: onItemsPressed ?? () => _openItems(context, sorted, index),
      ),
    );
    return _Section(
      title: '着用アイテム',
      onTitlePressed: onItemsPressed ?? () => _openItems(context, sorted),
      child: scrollable
          ? SizedBox(
              height:
                  tileWidth + 4 + MediaQuery.textScalerOf(context).scale(18),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                scrollDirection: Axis.horizontal,
                itemCount: sorted.length,
                itemBuilder: (_, index) => tile(index),
                separatorBuilder: (_, _) => const SizedBox(width: gap),
              ),
            )
          : Row(
              children: [
                for (var index = 0; index < sorted.length; index++) ...[
                  if (index > 0) const SizedBox(width: gap),
                  tile(index),
                ],
              ],
            ),
    );
  }

  void _openItems(
    BuildContext context,
    List<HomeOutfitItem> items, [
    int? selectedIndex,
  ]) {
    final heroTag = todayOutfitImage == null ? null : homeOutfitPhotoTag;
    if (onEditOutfit case final edit?) {
      edit(context, selectedIndex, heroTag);
      return;
    }
    final original = [
      for (final (index, item) in items.indexed) _reviewItem(item, index),
    ];
    if (!allowLocalOutfitEdits) {
      Navigator.of(context).push<void>(
        outfitReviewPhotoRoute(
          (_) => OutfitItemsReviewScreen(
            outfitImage: todayOutfitImage,
            heroTag: heroTag,
            initialItemIndex: selectedIndex,
            items: original,
            onRemove: null,
            statusLabel: '投稿済み',
          ),
          heroTag: heroTag,
        ),
      );
      return;
    }
    final draft = [...original];
    var nextIndex = original.length;
    Navigator.of(context).push<void>(
      outfitReviewPhotoRoute(
        (context) => StatefulBuilder(
          builder: (context, setState) => OutfitItemsReviewScreen(
            outfitImage: todayOutfitImage,
            heroTag: heroTag,
            initialItemIndex: selectedIndex,
            continueLabel: '投稿済み',
            items: [...draft],
            onRemove: (index) => setState(
              () => draft.removeWhere((item) => item.index == index),
            ),
            loadAddableItems: () async {
              final closet = await loadClosetItems?.call() ?? [];
              final used = draft
                  .map((item) => item.closetId ?? item.index)
                  .toSet();
              return [
                for (final item in original)
                  if (used.add(item.closetId ?? item.index)) item,
                for (final item in closet)
                  if (used.add(item.id ?? item)) _reviewItem(item, -1),
              ];
            },
            onItemAdded: (item) {
              final added = item.index < 0 ? item.withIndex(nextIndex++) : item;
              setState(() => draft.add(added));
              return added.index;
            },
          ),
        ),
        heroTag: heroTag,
      ),
    );
  }

  OutfitReviewItem _reviewItem(HomeOutfitItem item, int index) =>
      OutfitReviewItem(
        index: index,
        label: slotLabel(item.slot),
        closetId: item.id,
        searchLabel: item.label,
        slot: item.slot,
        image: item.image,
        memo: item.memo,
      );
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    this.onTitlePressed,
  });

  final String title;
  final Widget child;
  final VoidCallback? onTitlePressed;

  static const horizontalPadding = 6.0;
  static const titleStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.bold,
  );

  @override
  Widget build(BuildContext context) {
    final heading = Row(
      children: [
        Expanded(child: Text(title, style: titleStyle)),
        if (onTitlePressed != null)
          Icon(Icons.chevron_right, size: 20, color: context.palette.muted),
      ],
    );
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: context.palette.panel,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (onTitlePressed == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
              child: heading,
            )
          else
            InkWell(
              onTap: onTitlePressed,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                child: heading,
              ),
            ),
          child,
        ],
      ),
    );
  }
}

class _TodayOutfitHeader extends SliverPersistentHeaderDelegate {
  const _TodayOutfitHeader({
    required this.width,
    required this.image,
    required this.viewCount,
    required this.isPublishing,
    required this.onPublishPressed,
  });

  final double width;
  final ImageProvider? image;
  final int viewCount;
  final bool isPublishing;
  final VoidCallback onPublishPressed;

  static const _margin = EdgeInsets.symmetric(horizontal: 8);
  static const _expandedPadding = EdgeInsets.fromLTRB(6, 0, 6, 10);
  static const _compactPadding = EdgeInsets.fromLTRB(0, 8, 0, 6);

  @override
  double get minExtent => 68 + _compactPadding.vertical;

  @override
  double get maxExtent => math.max(
    minExtent,
    width -
        _margin.horizontal -
        _expandedPadding.horizontal +
        _expandedPadding.vertical,
  );

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final range = maxExtent - minExtent;
    final compact = range == 0 ? 1.0 : (shrinkOffset / range).clamp(0.0, 1.0);
    final detailsOpacity = (1 - compact * 2).clamp(0.0, 1.0);
    final shade = LinearGradient.lerp(
      const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, Color(0x99000000)],
        stops: [0.6, 1],
      ),
      const LinearGradient(
        colors: [Color(0xb3000000), Colors.transparent],
        stops: [0, 0.65],
      ),
      compact,
    )!;
    return ColoredBox(
      color: context.palette.canvas,
      child: Padding(
        padding: _margin,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Color.lerp(
              context.palette.panel,
              context.palette.canvas,
              compact,
            ),
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(20),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.lerp(
              _expandedPadding,
              _compactPadding,
              compact,
            )!,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (image case final photo?)
                    HomeOutfitPhotoHero(
                      image: photo,
                      alignment: Alignment.lerp(
                        Alignment.center,
                        const Alignment(0, -0.55),
                        compact,
                      )!,
                      background: context.palette.control,
                      shade: shade,
                    )
                  else ...[
                    ColoredBox(
                      color: context.palette.control,
                      child: Icon(
                        Icons.person_outline,
                        size: lerpDouble(72, 40, compact),
                        color: context.palette.muted,
                      ),
                    ),
                    DecoratedBox(decoration: BoxDecoration(gradient: shade)),
                  ],
                  if (detailsOpacity > 0)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Opacity(
                        opacity: detailsOpacity,
                        child: _PublishChip(
                          isPublishing: isPublishing,
                          onPressed: onPublishPressed,
                        ),
                      ),
                    ),
                  Align(
                    alignment: Alignment.lerp(
                      Alignment.bottomLeft,
                      Alignment.centerLeft,
                      compact,
                    )!,
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: lerpDouble(14, 16, compact)!,
                        bottom: lerpDouble(12, 0, compact)!,
                      ),
                      child: Semantics(
                        label: '今日見られた回数 $viewCount回',
                        child: ExcludeSemantics(
                          child: FittedBox(
                            alignment: Alignment.centerLeft,
                            fit: BoxFit.scaleDown,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (detailsOpacity > 0)
                                  ClipRect(
                                    child: Align(
                                      alignment: Alignment.bottomLeft,
                                      widthFactor: 1,
                                      heightFactor: detailsOpacity,
                                      child: Opacity(
                                        opacity: detailsOpacity,
                                        child: const Text(
                                          '今日見られた回数',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text(
                                      '$viewCount',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: lerpDouble(42, 38, compact),
                                        fontWeight: FontWeight.bold,
                                        height: 1.1,
                                      ),
                                    ),
                                    if (detailsOpacity > 0)
                                      Opacity(
                                        opacity: detailsOpacity,
                                        child: const Padding(
                                          padding: EdgeInsets.only(left: 3),
                                          child: Text(
                                            '回',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_TodayOutfitHeader oldDelegate) =>
      oldDelegate.width != width ||
      oldDelegate.image != image ||
      oldDelegate.viewCount != viewCount ||
      oldDelegate.isPublishing != isPublishing ||
      oldDelegate.onPublishPressed != onPublishPressed;
}

class _PublishChip extends StatelessWidget {
  const _PublishChip({required this.isPublishing, required this.onPressed});

  final bool isPublishing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final foreground = isPublishing
        ? context.palette.canvas
        : context.palette.ink;
    return Material(
      color: isPublishing ? context.palette.ink : context.palette.canvas,
      shape: appActionShape,
      child: InkWell(
        onTap: onPressed,
        customBorder: appActionShape,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 36),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isPublishing ? Icons.sensors : Icons.sensors_off_outlined,
                  size: 16,
                  color: foreground,
                ),
                const SizedBox(width: 6),
                Text(
                  isPublishing ? '近くに公開中' : '非公開',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: foreground,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UnpostedOutfitHeader extends SliverPersistentHeaderDelegate {
  const _UnpostedOutfitHeader({
    required this.width,
    required this.onCapturePressed,
  });

  final double width;
  final VoidCallback onCapturePressed;

  static const _margin = EdgeInsets.symmetric(horizontal: 8);
  static const _expandedPadding = EdgeInsets.fromLTRB(6, 0, 6, 10);
  static const _compactPadding = EdgeInsets.fromLTRB(0, 6, 0, 6);

  @override
  double get minExtent => 76 + _compactPadding.vertical;

  @override
  double get maxExtent => math.max(
    minExtent,
    math.min(400.0, width - _margin.horizontal - _expandedPadding.horizontal) +
        _expandedPadding.vertical,
  );

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final range = maxExtent - minExtent;
    final collapse = range == 0 ? 1.0 : (shrinkOffset / range).clamp(0.0, 1.0);
    return ColoredBox(
      color: context.palette.canvas,
      child: Padding(
        padding: _margin,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Color.lerp(
              context.palette.panel,
              context.palette.canvas,
              collapse,
            ),
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(20),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.lerp(
              _expandedPadding,
              _compactPadding,
              collapse,
            )!,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: OutfitCapturePrompt(
                onCapturePressed: onCapturePressed,
                embedded: true,
                collapse: collapse,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _UnpostedOutfitHeader oldDelegate) =>
      width != oldDelegate.width ||
      onCapturePressed != oldDelegate.onCapturePressed;
}

class _FriendPostCard extends StatelessWidget {
  const _FriendPostCard({required this.post});

  final HomeFriendPost post;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: context.palette.panel,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    container: true,
                    button: post.onOpenProfile != null,
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        onTap: post.onOpenProfile,
                        borderRadius: BorderRadius.circular(10),
                        child: Row(
                          children: [
                            FriendAvatar(
                              radius: 16,
                              name: post.displayName,
                              image: post.profileImage,
                              crop: post.profileCrop,
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                post.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(post.timeLabel, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
          FriendOutfitPostBody(
            image: post.image,
            imageLabel: '${post.displayName}のコーデ',
            items: post.items,
            isGenerated: post.isGenerated,
            itemsPadding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
            liked: post.liked,
            onLike: post.onLike,
            onToggleSave: post.onToggleSave,
            isSaved: post.isSaved,
            onMatch: post.onMatch,
          ),
        ],
      ),
    );
  }
}
