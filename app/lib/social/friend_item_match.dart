import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../viewer/outfit_match_screen.dart';
import 'friend_outfit_items.dart';
import 'social_activity.dart';

/// フレンドの公開中の服を、近くのコーデと同じ照合画面で開く。
Future<void> openFriendItemMatch(
  BuildContext context,
  ApiClient api,
  SocialFriend friend,
  FriendOutfitItem item,
) async {
  final index = item.index;
  final date = friend.postDate;
  if (index == null || date == null) return;
  final card = await api.friendItemCard(
    friendId: friend.id,
    index: index,
    date: date,
    slot: item.slot,
    label: item.label,
    color: item.color,
  );
  if (!context.mounted) return;
  if (card.items.length != 1) throw StateError('照合する服がありません');
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) =>
          OutfitMatchScreen(api: api, card: card, item: card.items.single),
    ),
  );
}
