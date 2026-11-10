import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app/app_banner.dart';
import '../app/app_loading.dart';
import '../app/app_palette.dart';
import '../app/confirmation_sheet.dart';

import 'outfit_review_background.dart';

/// 処理後の着姿と切り抜きを確認するための表示用データ。
class OutfitReviewItem {
  const OutfitReviewItem({
    required this.index,
    required this.label,
    this.imageBytes,
    this.image,
    this.slot,
    this.closetId,
    this.searchLabel,
    this.color = '',
    this.memo = '',
    this.pattern,
    this.materialGuess,
  });
  final int index;
  final String label;
  final Uint8List? imageBytes;
  final ImageProvider? image;
  final String? slot;
  final String? closetId;
  final String? searchLabel;
  final String color;
  final String memo;
  final String? pattern;
  final String? materialGuess;

  ImageProvider? get thumbnail =>
      image ?? (imageBytes == null ? null : MemoryImage(imageBytes!));

  OutfitReviewItem withIndex(int index) => OutfitReviewItem(
    index: index,
    label: label,
    imageBytes: imageBytes,
    image: image,
    slot: slot,
    closetId: closetId,
    searchLabel: searchLabel,
    color: color,
    memo: memo,
    pattern: pattern,
    materialGuess: materialGuess,
  );
}

enum _AddMode { search, newItem }

PageRoute<T> outfitReviewPhotoRoute<T>(
  WidgetBuilder builder, {
  Object? heroTag,
}) {
  final expandsFromHome = heroTag == homeOutfitPhotoTag;
  return PageRouteBuilder<T>(
    transitionDuration: Duration(milliseconds: expandsFromHome ? 520 : 340),
    reverseTransitionDuration: Duration(
      milliseconds: expandsFromHome ? 400 : 280,
    ),
    pageBuilder: (context, _, _) => builder(context),
    transitionsBuilder: (context, animation, _, child) {
      if (MediaQuery.disableAnimationsOf(context)) return child;
      final opacity = expandsFromHome
          ? animation.drive(
              CurveTween(
                curve: const Interval(0, 0.70, curve: Curves.easeInOutCubic),
              ),
            )
          : animation;
      return FadeTransition(opacity: opacity, child: child);
    },
  );
}

class OutfitItemsReviewScreen extends StatefulWidget {
  const OutfitItemsReviewScreen({
    super.key,
    this.outfitImageBytes,
    this.outfitImage,
    this.heroTag,
    this.title,
    required this.items,
    required this.onRemove,
    this.onAdd,
    this.onContinue,
    this.loadAddableItems,
    this.onItemAdded,
    this.onMemoChanged,
    this.itemAccessory,
    this.statusLabel,
    this.isDemo = false,
    this.onToggleSave,
    this.canSave,
    this.isSaved,
    this.initialItemIndex,
    this.continueLabel = '次へ',
  });

  const OutfitItemsReviewScreen.view({
    Key? key,
    required ImageProvider outfitImage,
    required List<OutfitReviewItem> items,
    Object? heroTag,
    String? title,
    int? initialItemIndex,
    bool isDemo = false,
    Future<void> Function(int)? onToggleSave,
    bool Function(int)? canSave,
    bool Function(int)? isSaved,
  }) : this(
         key: key,
         outfitImage: outfitImage,
         items: items,
         heroTag: heroTag,
         title: title,
         initialItemIndex: initialItemIndex,
         isDemo: isDemo,
         onToggleSave: onToggleSave,
         canSave: canSave,
         isSaved: isSaved,
         onRemove: null,
       );

  final Uint8List? outfitImageBytes;
  final ImageProvider? outfitImage;
  final Object? heroTag;
  final String? title;
  final List<OutfitReviewItem> items;
  final void Function(int index)? onRemove;
  final VoidCallback? onAdd;
  final VoidCallback? onContinue;
  final Future<List<OutfitReviewItem>> Function()? loadAddableItems;
  final int Function(OutfitReviewItem item)? onItemAdded;
  final void Function(int index, String memo)? onMemoChanged;
  final Widget Function(int index)? itemAccessory;
  final String? statusLabel;
  final bool isDemo;
  final Future<void> Function(int)? onToggleSave;
  final bool Function(int)? canSave;
  final bool Function(int)? isSaved;
  final int? initialItemIndex;
  final String continueLabel;

  @override
  State<OutfitItemsReviewScreen> createState() =>
      _OutfitItemsReviewScreenState();
}

class _OutfitItemsReviewScreenState extends State<OutfitItemsReviewScreen> {
  static const _wornTileSpacing = 8.0;
  static const _actionMinimumSize = Size(0, 56);
  final _memoController = TextEditingController();
  final _addController = TextEditingController();
  final _wornStripController = ScrollController();
  final Map<int, String> _memos = {};
  int? _selectedIndex;
  _AddMode? _addMode;
  Future<List<OutfitReviewItem>>? _addableItems;
  bool _confirmingRemoval = false;
  bool _savingViewedItem = false;
  bool get _readOnly => widget.onRemove == null;
  bool get _hasSuggestions => !_readOnly && widget.itemAccessory != null;
  AppPalette get _colors => context.palette;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialItemIndex ?? widget.items.firstOrNull?.index;
    if (widget.initialItemIndex != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealInitialItem());
    }
    _updateMemo();
  }

  void _revealInitialItem() {
    if (!mounted || !_wornStripController.hasClients) return;
    final index = widget.items.indexWhere(
      (item) => item.index == _selectedIndex,
    );
    if (index < 0) return;

    final position = _wornStripController.position;
    final tileEnd =
        index * (_ReviewTile.width + _wornTileSpacing) + _ReviewTile.width;
    final offset = tileEnd - position.viewportDimension;
    if (offset > 0) position.jumpTo(offset);
  }

  @override
  void didUpdateWidget(covariant OutfitItemsReviewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.items.any((item) => item.index == _selectedIndex)) {
      _selectedIndex = widget.items.isEmpty ? null : widget.items.first.index;
      _updateMemo();
    }
  }

  @override
  void dispose() {
    _memoController.dispose();
    _addController.dispose();
    _wornStripController.dispose();
    super.dispose();
  }

  void _selectItem(int index) {
    if (_selectedIndex == index) return;
    setState(() {
      _selectedIndex = index;
      _updateMemo();
    });
  }

  Future<void> _confirmRemoval(OutfitReviewItem item) async {
    if (_confirmingRemoval) return;
    _confirmingRemoval = true;
    try {
      final confirmed = await showConfirmationSheet(
        context,
        title: '「${item.searchLabel ?? item.label}」を着用アイテムから外しますか？',
        icon: Icons.delete_outline,
        confirmLabel: '外す',
        image: item.thumbnail,
      );
      if (!mounted || confirmed != true) return;
      widget.onRemove?.call(item.index);
    } finally {
      _confirmingRemoval = false;
    }
  }

  void _updateMemo() {
    final item = widget.items
        .where((item) => item.index == _selectedIndex)
        .firstOrNull;
    _memoController.text = _memos[_selectedIndex] ?? item?.memo ?? '';
  }

  void _startAdding() {
    final load = widget.loadAddableItems;
    if (load == null || widget.onItemAdded == null) {
      widget.onAdd?.call();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      if (_addMode == null) _addableItems = Future.sync(load);
      _addMode = _AddMode.search;
      _addController.clear();
    });
  }

  void _closeAdding() {
    FocusScope.of(context).unfocus();
    setState(() => _addMode = null);
  }

  void _addItem(OutfitReviewItem item) {
    final index = widget.onItemAdded!(item);
    FocusScope.of(context).unfocus();
    setState(() {
      _addMode = null;
      _selectedIndex = index;
      _memoController.text = _memos[index] ?? item.memo;
    });
  }

  void _createFromMemo() {
    final memo = _addController.text.trim();
    if (memo.isEmpty) return;
    _addItem(OutfitReviewItem(index: -1, label: 'その他', memo: memo));
  }

  Widget _input({
    required TextEditingController controller,
    required String hint,
    required ValueChanged<String> onChanged,
    bool enabled = true,
    int? maxLength,
    IconData? icon,
    ValueChanged<String>? onSubmitted,
  }) => TextField(
    controller: controller,
    enabled: enabled,
    maxLength: maxLength,
    style: TextStyle(color: _colors.ink, fontSize: 14),
    onChanged: onChanged,
    onSubmitted: onSubmitted,
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: _colors.muted, fontSize: 12),
      prefixIcon: icon == null
          ? null
          : Icon(icon, color: _colors.muted, size: 18),
      prefixIconConstraints: const BoxConstraints(minWidth: 40),
      counterText: '',
      filled: true,
      fillColor: _colors.isDark ? Colors.white12 : _colors.control,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: _colors.muted, width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: _colors.ink),
      ),
    ),
  );

  void _startNewItem() {
    if (_addMode == _AddMode.newItem) return;
    setState(() {
      _addMode = _AddMode.newItem;
      _addController.clear();
    });
  }

  Widget _buildClosetStrip() => FutureBuilder(
    future: _addableItems,
    builder: (context, snapshot) {
      final query = _addMode == _AddMode.search
          ? _addController.text.trim().toLowerCase()
          : '';
      final matches = (snapshot.data ?? const <OutfitReviewItem>[]).where((
        item,
      ) {
        final searchText =
            '${item.label} ${item.searchLabel ?? ''} ${item.memo}';
        return searchText.toLowerCase().contains(query);
      }).toList();
      return ListView.separated(
        key: ValueKey(query),
        scrollDirection: Axis.horizontal,
        itemCount: 1 + (matches.isEmpty ? 1 : matches.length),
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _ReviewTile(
              label: '新しく追加',
              icon: Icons.add,
              selected: _addMode == _AddMode.newItem,
              onTap: _startNewItem,
            );
          }
          if (matches.isNotEmpty) {
            final item = matches[index - 1];
            return _ReviewTile(
              label: item.searchLabel ?? item.label,
              image: item.image,
              onTap: () => _addItem(item),
            );
          }
          return Center(child: _closetEmptyState(snapshot, query.isEmpty));
        },
      );
    },
  );

  Widget _closetEmptyState(
    AsyncSnapshot<List<OutfitReviewItem>> snapshot,
    bool emptyQuery,
  ) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const AppLoadingIndicator();
    }
    final message = snapshot.hasError
        ? 'クローゼットを読み込めませんでした'
        : emptyQuery
        ? '追加できるアイテムはありません'
        : '一致するアイテムがありません';
    return Text(message, style: TextStyle(color: _colors.muted, fontSize: 12));
  }

  Widget _buildWornStrip() => ListView.separated(
    controller: _wornStripController,
    scrollDirection: Axis.horizontal,
    itemCount: widget.items.length,
    separatorBuilder: (_, _) => const SizedBox(width: _wornTileSpacing),
    itemBuilder: (context, position) {
      final item = widget.items[position];
      return _ReviewTile(
        label: item.label,
        image: item.thumbnail,
        selected: item.index == _selectedIndex,
        onTap: () => _selectItem(item.index),
        onRemove: _readOnly ? null : () => _confirmRemoval(item),
      );
    },
  );

  Widget _buildItemDetails() {
    final item = widget.items
        .where((item) => item.index == _selectedIndex)
        .firstOrNull;
    if (item == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          item.searchLabel ?? item.label,
          style: TextStyle(
            color: _colors.ink,
            fontSize: 19,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (item.color.isNotEmpty)
          Text(item.color, style: TextStyle(color: _colors.muted)),
        if (item.pattern case final pattern? when pattern.isNotEmpty)
          Text(pattern, style: TextStyle(color: _colors.muted)),
        if (item.materialGuess case final material? when material.isNotEmpty)
          Text('素材（推定） $material', style: TextStyle(color: _colors.muted)),
        if (item.memo.isNotEmpty)
          Text(item.memo, style: TextStyle(color: _colors.muted)),
        if (widget.onToggleSave != null &&
            widget.canSave?.call(item.index) != false)
          OutlinedButton.icon(
            onPressed: _savingViewedItem
                ? null
                : () => _toggleViewedSave(item.index),
            icon: Icon(
              widget.isSaved?.call(item.index) == true
                  ? Icons.bookmark
                  : Icons.bookmark_border,
            ),
            label: Text(
              widget.isSaved?.call(item.index) == true ? '保存を解除' : 'アイテムを保存',
            ),
          ),
        if (widget.isDemo)
          Text(
            'AI 生成',
            textAlign: TextAlign.end,
            style: TextStyle(color: _colors.muted, fontSize: 11),
          ),
      ],
    );
  }

  Future<void> _toggleViewedSave(int index) async {
    setState(() => _savingViewedItem = true);
    try {
      await widget.onToggleSave!(index);
    } catch (_) {
      if (mounted) {
        showAppBanner(context, '保存を更新できませんでした', icon: Icons.error_outline);
      }
    } finally {
      if (mounted) setState(() => _savingViewedItem = false);
    }
  }

  Widget _buildEditor() {
    final adding = _addMode != null;
    final creating = _addMode == _AddMode.newItem;
    final item = widget.items
        .where((item) => item.index == _selectedIndex)
        .firstOrNull;
    final title = adding
        ? (creating ? '新しいアイテムのメモ' : 'クローゼットから追加')
        : (item == null ? 'メモ' : '${item.label}のメモ');
    final hint = adding
        ? (creating ? 'ブランド名や服の特徴を入力' : 'アイテム名・カテゴリ・メモで検索')
        : 'ブランド名などを入力（任意）';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.itemAccessory case final accessory?)
          SizedBox(
            height: MediaQuery.textScalerOf(context).scale(56),
            child: Align(
              alignment: Alignment.centerLeft,
              child: adding || item == null ? null : accessory(item.index),
            ),
          ),
        Text(title, style: TextStyle(color: _colors.ink, fontSize: 12)),
        const SizedBox(height: 6),
        _input(
          controller: adding ? _addController : _memoController,
          enabled: adding || item != null,
          hint: hint,
          maxLength: _addMode == _AddMode.search ? null : 100,
          icon: _addMode == _AddMode.search ? Icons.search : null,
          onChanged: adding
              ? (_) => setState(() {})
              : (value) {
                  if (item == null) return;
                  _memos[item.index] = value;
                  widget.onMemoChanged?.call(item.index, value);
                },
          onSubmitted: creating ? (_) => _createFromMemo() : null,
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildPanel(BuildContext context) {
    final items = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _addMode == null ? '着用アイテム' : 'クローゼット',
          style: TextStyle(color: _colors.ink, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 102,
          child: _readOnly && widget.items.isEmpty
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '表示できるアイテムはありません',
                    style: TextStyle(color: _colors.muted),
                  ),
                )
              : _addMode == null
              ? _buildWornStrip()
              : _buildClosetStrip(),
        ),
        if (widget.items.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SizedBox(
              height: 6,
              child: _addMode == null
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (final item in widget.items)
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: item.index == _selectedIndex
                                  ? _colors.ink
                                  : _colors.muted.withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    )
                  : null,
            ),
          ),
      ],
    );
    final actions = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_readOnly) ...[
          _buildItemDetails(),
          if (widget.statusLabel case final label?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                label,
                textAlign: TextAlign.end,
                style: TextStyle(color: _colors.muted),
              ),
            ),
        ] else ...[
          _buildEditor(),
          if (_hasSuggestions) const Spacer(),
          Row(
            children: [
              if (widget.onAdd != null || widget.onItemAdded != null) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _addMode == _AddMode.search
                        ? _closeAdding
                        : _startAdding,
                    icon: Icon(switch (_addMode) {
                      null => Icons.add,
                      _AddMode.search => Icons.close,
                      _AddMode.newItem => Icons.arrow_back,
                    }),
                    label: Text(switch (_addMode) {
                      null => 'アイテムを追加',
                      _AddMode.search => '閉じる',
                      _AddMode.newItem => '検索に戻る',
                    }, textAlign: TextAlign.center),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _colors.ink,
                      minimumSize: _actionMinimumSize,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      side: BorderSide(color: _colors.muted),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: FilledButton(
                  onPressed: _addMode == _AddMode.newItem
                      ? (_addController.text.trim().isEmpty
                            ? null
                            : _createFromMemo)
                      : widget.onContinue,
                  style: FilledButton.styleFrom(
                    backgroundColor: _colors.ink,
                    foregroundColor: _colors.canvas,
                    minimumSize: _actionMinimumSize,
                    disabledBackgroundColor: _colors.isDark
                        ? Colors.white24
                        : _colors.control,
                    disabledForegroundColor: _colors.muted,
                  ),
                  child: Text(
                    _addMode == _AddMode.newItem
                        ? 'メモで追加'
                        : widget.continueLabel,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
    final routeAnimation = ModalRoute.of(context)?.animation;
    Widget panel(Widget strip, Widget editor) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        strip,
        const SizedBox(height: 12),
        if (_hasSuggestions) Expanded(child: editor) else editor,
      ],
    );
    if (routeAnimation == null || MediaQuery.disableAnimationsOf(context)) {
      return _withPanelBackdrop(panel(items, actions));
    }

    Widget reveal(Widget child, Interval interval, double offset) {
      final entrance = routeAnimation.drive(CurveTween(curve: interval));
      return FadeTransition(
        opacity: entrance,
        child: SlideTransition(
          position: entrance.drive(
            Tween(begin: Offset(0, offset), end: Offset.zero),
          ),
          child: child,
        ),
      );
    }

    if (widget.heroTag != homeOutfitPhotoTag) {
      return reveal(
        _withPanelBackdrop(panel(items, actions)),
        const Interval(0.12, 1, curve: Curves.easeOutCubic),
        0.08,
      );
    }

    return _withPanelBackdrop(
      panel(
        reveal(
          items,
          const Interval(0.65, 0.96, curve: Curves.easeOutCubic),
          0.16,
        ),
        reveal(
          actions,
          const Interval(0.76, 1, curve: Curves.easeOutCubic),
          0.15,
        ),
      ),
      opacity: routeAnimation.drive(
        CurveTween(
          curve: const Interval(0.65, 0.96, curve: Curves.easeOutCubic),
        ),
      ),
    );
  }

  Widget _withPanelBackdrop(Widget content, {Animation<double>? opacity}) {
    final fadeHeight = _colors.isDark ? 128.0 : 176.0;
    final surface = _colors.canvas;
    final backdrop = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: fadeHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  surface.withValues(alpha: 0),
                  surface.withValues(alpha: 0.10),
                  surface.withValues(alpha: 0.40),
                  surface.withValues(alpha: 0.73),
                  surface.withValues(alpha: 0.92),
                  surface,
                ],
                stops: const [0, 0.22, 0.43, 0.64, 0.83, 1],
              ),
            ),
          ),
        ),
        Expanded(child: ColoredBox(color: surface)),
      ],
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: 16 - fadeHeight,
          left: -20,
          right: -20,
          bottom: -_panelBottomPadding,
          child: IgnorePointer(
            child: opacity == null
                ? backdrop
                : FadeTransition(opacity: opacity, child: backdrop),
          ),
        ),
        content,
      ],
    );
  }

  double get _panelBottomPadding => 24 + MediaQuery.paddingOf(context).bottom;

  @override
  Widget build(BuildContext context) {
    final bytes = widget.outfitImageBytes;
    return Scaffold(
      backgroundColor: _colors.isDark
          ? const Color(0xff242424)
          : _colors.canvas,
      body: Stack(
        fit: StackFit.expand,
        children: [
          OutfitReviewBackground.image(
            image:
                widget.outfitImage ??
                (bytes == null ? null : MemoryImage(bytes)),
            heroTag: widget.heroTag,
            light: !_colors.isDark,
            blurSigma: 20,
            showBottomShade: false,
          ),
          SafeArea(
            bottom: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final bottomPadding = _panelBottomPadding;
                final height = (constraints.maxHeight - 8 - bottomPadding)
                    .clamp(0.0, double.infinity);
                // 候補欄と大きめの操作ボタンが収まるよう、写真の表示領域を決める。
                // 狭い画面では縦にスクロールできる。
                final photoGap =
                    (height -
                            kMinInteractiveDimension -
                            MediaQuery.textScalerOf(context).scale(364))
                        .clamp(0.0, double.infinity);
                final panel = _buildPanel(context);
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, bottomPadding),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: height),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                tooltip: '戻る',
                                color: _colors.ink,
                                onPressed: () =>
                                    Navigator.of(context).maybePop(),
                                icon: const Icon(Icons.arrow_back),
                              ),
                              if (widget.title case final title?)
                                Expanded(
                                  child: Text(
                                    title,
                                    style: TextStyle(
                                      color: _colors.ink,
                                      fontWeight: FontWeight.bold,
                                      shadows: [
                                        Shadow(
                                          color: _colors.canvas,
                                          blurRadius: 5,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          if (_hasSuggestions) ...[
                            SizedBox(height: photoGap),
                            Expanded(child: panel),
                          ] else ...[
                            const Spacer(),
                            panel,
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({
    required this.label,
    required this.onTap,
    this.image,
    this.icon = Icons.checkroom_outlined,
    this.selected = false,
    this.onRemove,
  });

  final String label;
  final VoidCallback onTap;
  final ImageProvider? image;
  final IconData icon;
  final bool selected;
  final VoidCallback? onRemove;
  static const width = 84.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.palette;
    return SizedBox(
      width: width,
      child: Stack(
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: width,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.isDark ? Colors.white24 : colors.control,
                borderRadius: BorderRadius.circular(10),
                border: selected ? Border.all(color: colors.muted) : null,
              ),
              child: Column(
                children: [
                  Expanded(
                    child: image == null
                        ? Icon(icon, color: colors.ink, size: 32)
                        : Image(image: image!, fit: BoxFit.contain),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.ink, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
          if (onRemove != null)
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                tooltip: '$labelを外す',
                onPressed: onRemove,
                icon: Icon(Icons.cancel, color: colors.ink, size: 20),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }
}
