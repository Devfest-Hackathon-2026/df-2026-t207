import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_palette.dart';
import '../mypage/my_page_screen.dart';
import 'friend_outfit_post_body.dart';
import 'friend_item_match.dart';
import 'social_activity.dart';

class FriendProfileScreen extends StatelessWidget {
  const FriendProfileScreen({super.key, required this.friend, this.activity});

  final SocialFriend friend;
  final SocialActivity? activity;

  static Route<void> route(SocialFriend friend, SocialActivity activity) {
    unawaited(activity.refreshFriends());
    return MaterialPageRoute<void>(
      builder: (_) => FriendProfileScreen(friend: friend, activity: activity),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([activity]),
    builder: (context, _) => _buildProfile(
      context,
      activity?.friends.where((item) => item.id == friend.id).firstOrNull ??
          friend,
    ),
  );

  Widget _buildProfile(BuildContext context, SocialFriend friend) {
    final outfit = friend.todayOutfit;
    final social = activity;
    final connected = social?.connected == true && friend.postDate != null;
    final topInset = MediaQuery.paddingOf(context).top;
    final extraTextHeight = (MediaQuery.textScalerOf(context).scale(44) - 44)
        .clamp(0.0, 120.0);
    return Scaffold(
      backgroundColor: context.palette.isDark
          ? context.palette.canvas
          : myPageBackgroundColor,
      body: CustomScrollView(
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _FriendProfileHeader(
              friend: friend,
              topInset: topInset,
              extraTextHeight: extraTextHeight,
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(10, 14, 10, 104),
            sliver: SliverToBoxAdapter(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.palette.isDark
                      ? context.palette.panel
                      : const Color(0xfff2eff4),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Semantics(
                        header: true,
                        child: const Text(
                          '今日の投稿',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (outfit == null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            '今日の公開コーデはありません',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: context.palette.muted),
                          ),
                        )
                      else ...[
                        const SizedBox(height: 10),
                        FriendOutfitPostBody(
                          key: ValueKey((friend.id, friend.postDate)),
                          image: outfit,
                          imageLabel: '${friend.name}の今日のコーデ',
                          items: friend.todayItems,
                          isGenerated: friend.isGeneratedOutfit,
                          liked: friend.liked,
                          onLike: connected
                              ? (liked) => social!.setLike(friend, liked)
                              : null,
                          onToggleSave: connected
                              ? (index) => social!.toggleSave(friend, index)
                              : null,
                          isSaved: connected
                              ? (index) => social!.isSaved(friend, index)
                              : null,
                          onMatch: connected
                              ? (context, item) => openFriendItemMatch(
                                  context,
                                  social!.api!,
                                  friend,
                                  item,
                                )
                              : null,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FriendProfileHeader extends SliverPersistentHeaderDelegate {
  const _FriendProfileHeader({
    required this.friend,
    required this.topInset,
    required this.extraTextHeight,
  });

  final SocialFriend friend;
  final double topInset;
  final double extraTextHeight;

  @override
  double get minExtent =>
      MyPageHeader.compactHeight + topInset + extraTextHeight;

  @override
  double get maxExtent => MyPageHeader.expandedHeight + topInset;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final collapse = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    return ColoredBox(
      color: context.palette.isDark
          ? context.palette.canvas
          : myPageBackgroundColor,
      child: MyPageHeader(
        displayName: friend.name,
        image: friend.todayOutfit,
        remoteProfileImage: friend.profileImage,
        remoteProfileCrop: friend.profileCrop,
        showTitle: false,
        showFriendCount: false,
        postCount: friend.postCount,
        streakDays: friend.streakDays,
        collapse: collapse,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _FriendProfileHeader oldDelegate) =>
      friend != oldDelegate.friend ||
      topInset != oldDelegate.topInset ||
      extraTextHeight != oldDelegate.extraTextHeight;
}
