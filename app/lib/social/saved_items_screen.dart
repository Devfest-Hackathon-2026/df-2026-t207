import 'package:flutter/material.dart';

import '../api/social_models.dart';
import '../app/app_loading.dart';
import '../closet/closet_screen.dart';
import 'social_activity.dart';

class SavedItemsScreen extends StatefulWidget {
  const SavedItemsScreen({super.key, required this.activity});

  final SocialActivity activity;

  @override
  State<SavedItemsScreen> createState() => _SavedItemsScreenState();
}

class _SavedItemsScreenState extends State<SavedItemsScreen> {
  late Future<List<SavedItem>> _items = widget.activity.api!.getSaves();

  Future<void> _reload() async {
    final items = widget.activity.api!.getSaves();
    setState(() {
      _items = items;
    });
    try {
      await items;
    } catch (_) {
      // 読み込みエラーは一覧に表示する。
    }
  }

  Future<void> _delete(ClosetItem item) async {
    await widget.activity.deleteSave(item.id);
    if (mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<SavedItem>>(
    future: _items,
    builder: (context, snapshot) {
      final items = snapshot.data;
      if (items == null || snapshot.hasError) {
        return Scaffold(
          appBar: AppBar(title: const Text('保存したアイテム')),
          body: Center(
            child: snapshot.hasError
                ? TextButton(onPressed: _reload, child: const Text('一覧を再取得'))
                : const AppLoadingIndicator(),
          ),
        );
      }
      return AppRefreshIndicator(
        onRefresh: _reload,
        child: ClosetScreen.saved(
          items: [
            for (final item in items)
              ClosetItem(
                id: item.id,
                slot: item.slot,
                label: item.label,
                color: item.color,
                pattern: item.pattern,
                materialGuess: item.materialGuess,
              ),
          ],
          onBack: () => Navigator.of(context).pop(),
          onDelete: _delete,
        ),
      );
    },
  );
}
