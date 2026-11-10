import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/api_models.dart';
import '../closet/closet_screen.dart';
import 'app_loading.dart';
import 'app_palette.dart';

/// クローゼットの画面に api の手持ちを渡す。
class ClosetPage extends StatefulWidget {
  const ClosetPage({
    super.key,
    required this.api,
    required this.onAddPressed,
    this.onItemDeleted,
  });

  final ApiClient api;

  /// 追加 (今日のコーデを撮る)。呼ぶ前にこの画面は閉じる
  final VoidCallback onAddPressed;

  /// 手持ちから外したアイテムの ID。
  final ValueChanged<String>? onItemDeleted;

  @override
  State<ClosetPage> createState() => _ClosetPageState();
}

class _ClosetPageState extends State<ClosetPage> {
  List<WardrobeItem>? _items;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final items = await widget.api.getWardrobe();
      if (mounted) setState(() => _items = items);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _delete(ClosetItem item) async {
    await widget.api.deleteWardrobeItem(item.id);
    if (!mounted) return;
    setState(() => _items = [..._items!.where((i) => i.itemId != item.id)]);
    widget.onItemDeleted?.call(item.id);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items == null) {
      return Scaffold(
        appBar: AppBar(backgroundColor: context.palette.canvas, title: const Text('クローゼット')),
        body: Center(
          child: _failed
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('読み込めませんでした'),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _load, child: const Text('もう一度')),
                  ],
                )
              : const AppLoadingIndicator(),
        ),
      );
    }
    return AppRefreshIndicator(
      onRefresh: _load,
      child: ClosetScreen(
        items: [
          for (final i in items)
            ClosetItem(
              id: i.itemId,
              slot: i.slot,
              label: i.label,
              color: i.color,
              pattern: i.pattern,
              materialGuess: i.materialGuess,
              memo: i.memo,
              image: widget.api.image(i.image),
            ),
        ],
        onBack: () => Navigator.of(context).pop(),
        onAddPressed: () {
          Navigator.of(context).pop();
          widget.onAddPressed();
        },
        onDelete: _delete,
      ),
    );
  }
}
