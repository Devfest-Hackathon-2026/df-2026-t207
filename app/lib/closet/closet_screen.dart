import 'package:flutter/material.dart';

import '../app/app_loading.dart';
import '../app/app_palette.dart';
import '../app/confirmation_sheet.dart';
import '../common/outfit_item_tile.dart';

/// クローゼットに出す服 1 着。
class ClosetItem {
  const ClosetItem({
    required this.id,
    required this.slot,
    required this.label,
    this.color,
    this.pattern,
    this.materialGuess,
    this.memo,
    this.image,
  });

  final String id;

  /// API の `slot` (outer / top / bottom / dress / shoes / bag / accessory)
  final String slot;
  final String label;
  final String? color;
  final String? pattern;

  /// AI の推定。画面では「推定」と出す
  final String? materialGuess;
  final String? memo;
  final ImageProvider? image;
}

/// クローゼット (仕様書の S11)。登録した服 (手持ち) の一覧。
///
/// 区分で絞り、タップで詳しく見る。外す (手持ちから消す) こともできる。
/// データの取得と行き来は呼び出し側から渡す。
class ClosetScreen extends StatefulWidget {
  const ClosetScreen({
    super.key,
    required this.items,
    required this.onBack,
    required VoidCallback this.onAddPressed,
    this.onDelete,
  }) : _saved = false;

  const ClosetScreen.saved({
    super.key,
    required this.items,
    required this.onBack,
    required this.onDelete,
  }) : onAddPressed = null,
       _saved = true;

  final List<ClosetItem> items;
  final VoidCallback onBack;

  /// 追加 (今日のコーデを撮る)
  final VoidCallback? onAddPressed;
  final bool _saved;

  /// クローゼットから外す。失敗したら例外を投げる (画面が知らせる)。null なら外すボタンを出さない
  final Future<void> Function(ClosetItem item)? onDelete;

  @override
  State<ClosetScreen> createState() => _ClosetScreenState();
}

class _ClosetScreenState extends State<ClosetScreen> {
  /// null は「すべて」
  String? _slot;

  /// 絞り込みの並び。仕様書の 4 つに加え、持っている時だけワンピース・バッグ・小物も出す
  List<String> get _slots {
    const base = ['outer', 'top', 'bottom', 'shoes'];
    final extra = ['dress', 'bag', 'accessory']
        .where((s) => widget.items.any((i) => i.slot == s));
    return [...base, ...extra]..sort((a, b) => slotOrder(a).compareTo(slotOrder(b)));
  }

  @override
  void didUpdateWidget(covariant ClosetScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_slot != null && !_slots.contains(_slot)) _slot = null;
  }

  Future<void> _openDetail(ClosetItem item) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _ItemDetailSheet(
        item: item,
        onDelete: widget.onDelete,
        saved: widget._saved,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final i in widget.items)
        if (_slot == null || i.slot == _slot) i,
    ];
    if (!widget._saved) {
      shown.sort((a, b) => slotOrder(a.slot).compareTo(slotOrder(b.slot)));
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: widget.onBack,
                    tooltip: '戻る',
                    icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                  ),
                  Expanded(
                    child: Text(
                      widget._saved ? '保存したアイテム' : 'クローゼット',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'アイテム ${widget.items.length}点',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.palette.muted,
                      ),
                    ),
                  ),
                  if (widget.onAddPressed case final add?)
                    FilledButton.icon(
                      onPressed: add,
                      style: FilledButton.styleFrom(
                        backgroundColor: context.palette.ink,
                        foregroundColor: context.palette.canvas,
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      // 日本語の字は行の上下の余白が偏って下にずれるので、余白を上下に均して＋と高さを揃える
                      label: const Text(
                        '追加',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          height: 1,
                          leadingDistribution: TextLeadingDistribution.even,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (widget.items.isNotEmpty)
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _FilterChip(
                      label: 'すべて',
                      selected: _slot == null,
                      onTap: () => setState(() => _slot = null),
                    ),
                    for (final s in _slots)
                      _FilterChip(
                        label: slotLabel(s),
                        selected: _slot == s,
                        onTap: () => setState(() => _slot = s),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  if (shown.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: widget.items.isEmpty
                          ? _Empty(onAddPressed: widget.onAddPressed)
                          : Center(
                              child: Text(
                                '${slotLabel(_slot!)}はまだありません',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: context.palette.muted,
                                ),
                              ),
                            ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      sliver: SliverGrid.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 10,
                              childAspectRatio: 0.78,
                            ),
                        itemCount: shown.length,
                        itemBuilder: (context, i) => OutfitItemTile(
                          label: shown[i].label,
                          image: shown[i].image,
                          onTap: () => _openDetail(shown[i]),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Center(
        child: Semantics(
          selected: selected,
          button: true,
          child: Material(
            color: selected ? context.palette.ink : context.palette.canvas,
            shape: StadiumBorder(
              side: BorderSide(
                color: selected ? context.palette.ink : context.palette.outline,
              ),
            ),
            child: InkWell(
              onTap: onTap,
              customBorder: const StadiumBorder(),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 36),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: selected ? context.palette.canvas : context.palette.ink,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({this.onAddPressed});

  final VoidCallback? onAddPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.checkroom_outlined,
              size: 44,
              color: context.palette.muted,
            ),
            const SizedBox(height: 12),
            Text(
              onAddPressed == null ? '保存したアイテムはありません' : 'クローゼットにアイテムはありません',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            if (onAddPressed case final add?) ...[
              const SizedBox(height: 6),
              Text(
                '今日のコーデを撮ると、着ている服がここに入ります。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: context.palette.muted,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: add,
                  style: FilledButton.styleFrom(
                    backgroundColor: context.palette.ink,
                    foregroundColor: context.palette.canvas,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                  ),
                  icon: const Icon(Icons.photo_camera_outlined, size: 20),
                  label: const Text(
                    '今日のコーデを撮る',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ItemDetailSheet extends StatefulWidget {
  const _ItemDetailSheet({
    required this.item,
    required this.onDelete,
    required this.saved,
  });

  final ClosetItem item;
  final Future<void> Function(ClosetItem item)? onDelete;
  final bool saved;

  @override
  State<_ItemDetailSheet> createState() => _ItemDetailSheetState();
}

class _ItemDetailSheetState extends State<_ItemDetailSheet> {
  bool _deleting = false;
  bool _failed = false;

  Future<void> _delete() async {
    final ok = widget.saved
        ? await showConfirmationSheet(
            context,
            title: '「${widget.item.label}」の保存を解除しますか？',
            icon: Icons.bookmark_remove_outlined,
            confirmLabel: '解除',
          )
        : await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('クローゼットから外しますか？'),
              content: Text('「${widget.item.label}」をクローゼットから外します。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('やめる'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('外す'),
                ),
              ],
            ),
          );
    if (ok != true || !mounted) return;
    setState(() {
      _deleting = true;
      _failed = false;
    });
    try {
      await widget.onDelete!(widget.item);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _deleting = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final rows = [
      ('区分', slotLabel(item.slot)),
      if (item.color != null && item.color!.isNotEmpty) ('色', item.color!),
      if (item.pattern != null && item.pattern!.isNotEmpty)
        ('柄', item.pattern!),
      if (item.materialGuess != null && item.materialGuess!.isNotEmpty)
        ('素材 (推定)', item.materialGuess!),
      if (item.memo != null && item.memo!.isNotEmpty) ('メモ', item.memo!),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.palette.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.palette.control,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: item.image == null
                    ? Icon(
                        Icons.checkroom_outlined,
                        size: 56,
                        color: context.palette.muted,
                      )
                    : Padding(
                        padding: const EdgeInsets.all(16),
                        child: Image(image: item.image!, fit: BoxFit.contain),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              item.label,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            for (final (k, v) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  // ラベルと値は文字の大きさが違うので、上端ではなく文字の下の線で揃える
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(
                        k,
                        style: TextStyle(
                          fontSize: 13,
                          color: context.palette.muted,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(v, style: const TextStyle(fontSize: 14)),
                    ),
                  ],
                ),
              ),
            if (widget.onDelete != null) ...[
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: _deleting ? null : _delete,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.palette.danger,
                    side: BorderSide(color: context.palette.outline),
                  ),
                  child: _deleting
                      ? const AppLoadingIndicator()
                      : Text(
                          widget.saved ? '保存を解除' : 'クローゼットから外す',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),
              if (_failed)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    widget.saved
                        ? '保存を解除できませんでした。もう一度お試しください。'
                        : '外せませんでした。もう一度お試しください。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.palette.danger,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
