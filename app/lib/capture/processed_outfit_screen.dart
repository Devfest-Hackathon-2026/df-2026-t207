import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/api_models.dart';
import '../app/app_banner.dart';
import '../app/app_loading.dart';
import '../app/app_palette.dart';
import '../common/outfit_item_tile.dart';
import '../register/outfit_job.dart';
import 'outfit_items_review_screen.dart';

class ProcessedOutfitScreen extends StatefulWidget {
  const ProcessedOutfitScreen({
    super.key,
    required this.api,
    required this.jobId,
    required OutfitJob this.outfit,
  }) : existing = null,
       heroTag = null,
       initialItemIndex = null;

  const ProcessedOutfitScreen.edit({
    super.key,
    required this.api,
    required this.jobId,
    required TodayOutfit outfit,
    required this.heroTag,
    this.initialItemIndex,
  }) : existing = outfit,
       outfit = null;

  final ApiClient api;
  final String jobId;
  final OutfitJob? outfit;
  final TodayOutfit? existing;
  final Object? heroTag;
  final int? initialItemIndex;

  @override
  State<ProcessedOutfitScreen> createState() => _ProcessedOutfitScreenState();
}

class _ProcessedOutfitScreenState extends State<ProcessedOutfitScreen> {
  late final _detectedIndices =
      widget.outfit?.items.map((item) => item.index).toSet() ?? <int>{};
  late final _items = _initialItems();
  late int _nextIndex =
      1 + _items.fold(-1, (highest, item) => math.max(highest, item.index));
  late var _suggestions = widget.api.sameItems(widget.jobId);
  final _memos = <int, String>{};
  final _sameAs = <int, String>{};
  bool _saving = false;
  bool _dirty = false;

  List<OutfitReviewItem> _initialItems() {
    final existing = widget.existing;
    if (existing == null) {
      return [
        for (final item in widget.outfit!.items)
          OutfitReviewItem(
            index: item.index,
            label: slotLabel(item.slot),
            searchLabel: item.label,
            color: item.color ?? '',
            slot: item.slot,
            image: widget.api.image(item.image),
          ),
      ];
    }
    final items =
        [
          for (final item in existing.items) _closetItem(item),
          for (final memo in existing.itemNotes)
            OutfitReviewItem(index: -1, label: 'その他', memo: memo),
        ]..sort(
          (a, b) => slotOrder(a.slot ?? '').compareTo(slotOrder(b.slot ?? '')),
        );
    return [for (final (index, item) in items.indexed) item.withIndex(index)];
  }

  OutfitReviewItem _closetItem(WardrobeItem item) => OutfitReviewItem(
    index: -1,
    closetId: item.itemId,
    label: slotLabel(item.slot),
    searchLabel: item.label,
    slot: item.slot,
    color: item.color,
    image: widget.api.image(item.image),
    memo: item.memo ?? '',
  );

  Future<List<OutfitReviewItem>> _loadCloset() async {
    final wardrobe = await widget.api.getWardrobe();
    final used = {..._sameAs.values, ..._items.map((item) => item.closetId)};
    return [
      for (final item in wardrobe)
        if (!used.contains(item.itemId)) _closetItem(item),
    ];
  }

  int _add(OutfitReviewItem item) {
    final added = item.withIndex(_nextIndex++);
    setState(() {
      _items.add(added);
      _dirty = true;
    });
    return added.index;
  }

  void _remove(int index) => setState(() {
    _items.removeWhere((item) => item.index == index);
    _memos.remove(index);
    _sameAs.remove(index);
    _dirty = true;
  });

  String _memoFor(OutfitReviewItem item) => _memos[item.index] ?? item.memo;

  bool get _canSave =>
      !_saving &&
      (widget.existing == null || _dirty) &&
      _items.every(
        (item) =>
            _detectedIndices.contains(item.index) ||
            item.closetId != null ||
            _memoFor(item).trim().isNotEmpty,
      );

  Future<void> _register() async {
    if (!_canSave) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      final outfit = await widget.api.registerTodayOutfit(
        widget.jobId,
        [
          for (final item in _items)
            if (_detectedIndices.contains(item.index))
              (index: item.index, memo: _memoFor(item)),
        ],
        sameAs: _sameAs,
        editDate: widget.existing?.date,
        addedItems: [
          for (final item in _items)
            if (!_detectedIndices.contains(item.index))
              (wardrobeItemId: item.closetId, memo: _memoFor(item)),
        ],
      );
      if (mounted) Navigator.pop(context, outfit);
    } catch (error) {
      if (!mounted) return;
      showAppBanner(
        context,
        error is ApiException
            ? error.message
            : widget.existing == null
            ? 'コーデを投稿できませんでした'
            : '変更を保存できませんでした',
        icon: Icons.error_outline,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _sameItem(int index) => FutureBuilder<List<SameItem>>(
    future: _suggestions,
    builder: (context, snapshot) {
      final colors = context.palette;
      final statusStyle = TextStyle(color: colors.muted, fontSize: 14);
      if (snapshot.connectionState != ConnectionState.done) {
        return Row(
          children: [
            AppLoadingIndicator(color: colors.muted),
            const SizedBox(width: 8),
            Expanded(child: Text('手持ちに同じ服があるか確認しています', style: statusStyle)),
          ],
        );
      }
      if (snapshot.hasError) {
        return TextButton(
          style: TextButton.styleFrom(foregroundColor: colors.ink),
          onPressed: () =>
              setState(() => _suggestions = widget.api.sameItems(widget.jobId)),
          child: const Text('同じ服の候補を再確認'),
        );
      }
      final candidate = snapshot.data
          ?.where((item) => item.index == index)
          .firstOrNull;
      if (candidate == null) {
        return Text('このアイテムと同じ服は手持ちにありません', style: statusStyle);
      }
      final item = candidate.wardrobeItem;
      final used = _items.any(
        (other) =>
            other.closetId == item.itemId ||
            (other.index != index && _sameAs[other.index] == item.itemId),
      );
      return CheckboxListTile(
        dense: true,
        activeColor: colors.ink,
        checkColor: colors.canvas,
        side: BorderSide(color: colors.muted),
        value: _sameAs[index] == item.itemId,
        onChanged: used
            ? null
            : (use) => setState(() {
                if (use == true) {
                  _sameAs[index] = item.itemId;
                } else {
                  _sameAs.remove(index);
                }
              }),
        contentPadding: EdgeInsets.zero,
        title: Text(
          '手持ちの「${item.label}」を使う',
          style: TextStyle(color: colors.ink),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        secondary: SizedBox.square(
          dimension: 40,
          child: Image(
            image: widget.api.image(item.image),
            fit: BoxFit.contain,
          ),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    final image = widget.outfit?.outfitImage ?? existing?.image;
    return PopScope(
      canPop: !_saving,
      child: AbsorbPointer(
        absorbing: _saving,
        child: OutfitItemsReviewScreen(
          outfitImage: image == null
              ? null
              : widget.api.image(image, version: existing),
          heroTag: widget.heroTag,
          initialItemIndex: widget.initialItemIndex,
          items: [..._items],
          onRemove: _remove,
          onMemoChanged: (index, memo) => setState(() {
            _memos[index] = memo;
            _dirty = true;
          }),
          loadAddableItems: _loadCloset,
          onItemAdded: _items.length < 20 ? _add : null,
          itemAccessory: existing == null
              ? (index) => _detectedIndices.contains(index)
                    ? _sameItem(index)
                    : const SizedBox.shrink()
              : null,
          onContinue: _canSave ? _register : null,
          continueLabel: _saving
              ? (existing == null ? '投稿中…' : '保存中…')
              : existing == null
              ? 'コーデを投稿'
              : _dirty
              ? '変更を保存'
              : '投稿済み',
        ),
      ),
    );
  }
}
