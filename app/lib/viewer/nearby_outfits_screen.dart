import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_models.dart';
import '../app/app_banner.dart';
import '../app/app_loading.dart';
import '../app/app_palette.dart';
import '../app/confirmation_sheet.dart';
import '../common/outfit_capture_prompt.dart';
import '../common/outfit_item_tile.dart';

enum _SafetyAction { block, report }

/// S4 と S5。カードの取得は画面を開いた時にだけ行う。
class NearbyOutfitsScreen extends StatefulWidget {
  const NearbyOutfitsScreen({
    super.key,
    required this.loadNearby,
    required this.imageFor,
    this.onBlock,
    this.onReport,
    this.onMatch,
    this.onSetLike,
    this.onCardShown,
    this.onSaveItem,
    this.onDeleteSave,
    this.onCapturePressed,
    this.outfitToPublish,
    this.onPublishPressed,
    this.isSimulated = false,
    this.showPreviewLabels = true,
    this.initialDetails = false,
    this.initialItemId,
    this.initialLiked = false,
    this.initialSavedItemIds = const {},
    this.canMatchItem,
    this.canSaveItem,
    this.showLike = true,
    this.showSave = true,
  });

  final Future<NearbyResult> Function() loadNearby;
  final ImageProvider? Function(String path) imageFor;
  final Future<void> Function(String cardId)? onBlock;
  final Future<void> Function(String cardId, String reason)? onReport;
  final FutureOr<void> Function(NearbyCard card, CardItem item)? onMatch;
  final Future<void> Function(String cardId, bool liked)? onSetLike;

  /// 表示中のカードが替わった時 (Web デモの外枠で、すれ違った人 A の画面に出す)
  final void Function(NearbyCard card)? onCardShown;
  final Future<String> Function(String cardId, String itemId)? onSaveItem;
  final Future<void> Function(String saveId)? onDeleteSave;
  final VoidCallback? onCapturePressed;
  final ImageProvider? outfitToPublish;
  final Future<void> Function()? onPublishPressed;
  final bool isSimulated;
  final bool showPreviewLabels;
  final bool initialDetails;
  final String? initialItemId;
  final bool initialLiked;
  final Set<String> initialSavedItemIds;
  final bool Function(CardItem)? canMatchItem;
  final bool Function(CardItem)? canSaveItem;
  final bool showLike;
  final bool showSave;

  @override
  State<NearbyOutfitsScreen> createState() => _NearbyOutfitsScreenState();
}

class _NearbyOutfitsScreenState extends State<NearbyOutfitsScreen> {
  final _pages = PageController();
  final _liked = <String>{};
  final _saved = <(String, String), String>{};
  bool _updatingReaction = false;
  List<NearbyCard> _cards = const [];
  int _index = 0;
  bool _loading = true;
  bool _failed = false;
  bool _viewerPublishing = true;
  bool _details = false;
  bool _sending = false;
  bool _matching = false;
  double _verticalDrag = 0;
  CardItem? _selected;
  Timer? _expiry;

  AppPalette get _colors => context.palette;

  ButtonStyle get _actionButton => FilledButton.styleFrom(
    backgroundColor: _colors.ink,
    foregroundColor: _colors.canvas,
    disabledBackgroundColor: _colors.control,
    disabledForegroundColor: _colors.muted,
    minimumSize: const Size(0, 48),
    padding: const EdgeInsets.symmetric(horizontal: 20),
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final result = await widget.loadNearby();
      if (!mounted) return;
      final now = DateTime.now();
      setState(() {
        _cards = result.cards
            .where((card) => card.expiresAt.isAfter(now))
            .toList();
        _index = 0;
        _viewerPublishing = result.viewerPublishing;
        _loading = false;
        if (_cards.isNotEmpty && widget.initialDetails) {
          final card = _cards.first;
          _details = true;
          _selected = card.items
              .where((item) => item.cardItemId == widget.initialItemId)
              .firstOrNull;
          if (widget.initialLiked) _liked.add(card.cardId);
          for (final id in widget.initialSavedItemIds) {
            _saved[(card.cardId, id)] = id;
          }
        }
      });
      _watchExpiry();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  void _watchExpiry() {
    _expiry?.cancel();
    final now = DateTime.now();
    final deadlines = [
      for (final card in _cards)
        if (card.expiresAt.isAfter(now)) card.expiresAt,
    ]..sort();
    if (deadlines.isEmpty) return;
    _expiry = Timer(deadlines.first.difference(now), () {
      setState(() {});
      _watchExpiry();
    });
  }

  @override
  void dispose() {
    _expiry?.cancel();
    _pages.dispose();
    super.dispose();
  }

  void _showDetails(bool show) => setState(() {
    _details = show;
    _selected = null;
  });

  void _finishVerticalDrag(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (!_details && (_verticalDrag >= 28 || velocity > 300)) {
      _showDetails(true);
    } else if (_details && (_verticalDrag <= -28 || velocity < -300)) {
      _showDetails(false);
    }
  }

  void _message(String message, {IconData icon = Icons.info_outline}) =>
      showAppBanner(context, message, icon: icon);

  Future<void> _publish() async {
    if (_sending) return;
    final confirmed = await showConfirmationSheet(
      context,
      title: '今日のコーデを公開しますか？',
      message: '近くのユーザーに公開します。公開は今日の24時に終了します。',
      icon: Icons.public_outlined,
      confirmLabel: '公開する',
      destructive: false,
    );
    if (!mounted || confirmed != true || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.onPublishPressed!();
      if (mounted) await _load();
    } catch (_) {
      if (mounted) {
        _message('公開できませんでした。設定を確認してもう一度お試しください', icon: Icons.error_outline);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openSafetyMenu(NearbyCard card) async {
    final action = await showActionSheet<_SafetyAction>(
      context,
      actions: [
        if (widget.onBlock != null)
          (value: _SafetyAction.block, label: 'ブロック', destructive: false),
        (value: null, label: 'キャンセル', destructive: false),
        if (widget.onReport != null)
          (value: _SafetyAction.report, label: '通報', destructive: false),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case _SafetyAction.block:
        await _block(card);
      case _SafetyAction.report:
        await _report(card);
      case null:
        break;
    }
  }

  Future<void> _block(NearbyCard card) async {
    final confirmed = await showConfirmationSheet(
      context,
      title: 'この人をブロックしますか？',
      icon: Icons.block_outlined,
      confirmLabel: 'ブロック',
    );
    if (!mounted || confirmed != true) return;
    await _sendSafetyAction(() async {
      await widget.onBlock!(card.cardId);
      if (!mounted) return;
      setState(() {
        _cards = _cards.where((entry) => entry.cardId != card.cardId).toList();
        _index = _cards.isEmpty ? 0 : _index.clamp(0, _cards.length - 1);
        _details = false;
        _selected = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pages.hasClients) _pages.jumpToPage(_index);
      });
      _watchExpiry();
      _message('ブロックしました', icon: Icons.check_circle_outline);
    });
  }

  Future<void> _report(NearbyCard card) async {
    const reasons = {
      'inappropriate': '不適切な内容',
      'not_clothes': '服の画像ではない',
      'harassment': '嫌がらせ',
      'other': 'その他',
    };
    final reason = await showActionSheet<String>(
      context,
      title: '通報理由',
      icon: Icons.flag_outlined,
      actions: [
        for (final entry in reasons.entries)
          (value: entry.key, label: entry.value, destructive: false),
        (value: null, label: 'キャンセル', destructive: false),
      ],
    );
    if (!mounted || reason == null) return;
    await _sendSafetyAction(() async {
      await widget.onReport!(card.cardId, reason);
      if (mounted) _message('通報を受け付けました', icon: Icons.check_circle_outline);
    });
  }

  Future<void> _sendSafetyAction(Future<void> Function() action) async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await action();
    } on ApiException catch (error) {
      if (mounted) {
        _message(
          error.statusCode == 410 ? 'もう見られません' : '送信できませんでした',
          icon: Icons.error_outline,
        );
      }
    } catch (_) {
      if (mounted) _message('送信できませんでした', icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = _cards.isEmpty ? null : _cards[_index];
    final isCurrent = card != null && card.expiresAt.isAfter(DateTime.now());
    final showsDetails = _details && isCurrent;
    final showsEmpty =
        !_loading && !_failed && card == null && _viewerPublishing;
    final showsPhotoPrompt =
        !_loading &&
        !_failed &&
        card == null &&
        !_viewerPublishing &&
        ((widget.outfitToPublish != null && widget.onPublishPressed != null) ||
            widget.onCapturePressed != null);
    return PopScope(
      canPop: !_details || widget.initialDetails,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _details && !widget.initialDetails) _showDetails(false);
      },
      child: Scaffold(
        backgroundColor: _colors.loadingBackground,
        body: AnnotatedRegion<SystemUiOverlayStyle>(
          value: showsPhotoPrompt
              ? SystemUiOverlayStyle.light
              : _colors.systemOverlays,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            onVerticalDragStart: isCurrent && !widget.initialDetails
                ? (_) => _verticalDrag = 0
                : null,
            onVerticalDragUpdate: isCurrent && !widget.initialDetails
                ? (event) => _verticalDrag += event.primaryDelta ?? 0
                : null,
            onVerticalDragEnd: isCurrent && !widget.initialDetails
                ? _finishVerticalDrag
                : null,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_loading)
                  const Center(child: AppLoadingIndicator())
                else if (_failed)
                  _empty('近くのコーデを取得できませんでした', '再試行', _load)
                else if (card == null &&
                    !_viewerPublishing &&
                    widget.outfitToPublish != null &&
                    widget.onPublishPressed != null)
                  OutfitCapturePrompt(
                    outfitToPublish: widget.outfitToPublish,
                    onCapturePressed: _sending ? null : _publish,
                  )
                else if (card == null &&
                    !_viewerPublishing &&
                    widget.onCapturePressed != null)
                  OutfitCapturePrompt(
                    onCapturePressed: widget.onCapturePressed!,
                  )
                else if (showsEmpty)
                  _noNearbyOutfits()
                else if (card == null)
                  _empty(
                    '今日のコーデを公開すると見られます',
                    'ホームへ戻る',
                    () => Navigator.pop(context),
                  )
                else
                  PageView.builder(
                    controller: _pages,
                    physics: _details
                        ? const NeverScrollableScrollPhysics()
                        : null,
                    itemCount: _cards.length,
                    onPageChanged: (index) {
                      if (index >= _cards.length) return;
                      setState(() {
                        _index = index;
                        _selected = null;
                      });
                      widget.onCardShown?.call(_cards[index]);
                    },
                    itemBuilder: (context, index) {
                      final entry = _cards[index];
                      if (!entry.expiresAt.isAfter(DateTime.now())) {
                        return Center(
                          child: Text(
                            'もう見られません',
                            style: TextStyle(color: _colors.ink),
                          ),
                        );
                      }
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: showsDetails && !widget.initialDetails
                            ? () => _showDetails(false)
                            : null,
                        child: _OutfitPhoto(
                          image: widget.imageFor(entry.image),
                          details: _details,
                        ),
                      );
                    },
                  ),
                if (card != null && !_loading)
                  SafeArea(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Listener(
                        behavior: showsDetails
                            ? HitTestBehavior.opaque
                            : HitTestBehavior.deferToChild,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 34),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (showsDetails)
                                _buildDetails(card)
                              else
                                _buildCardIndicators(card, isCurrent),
                              if (isCurrent) ...[
                                SizedBox(height: showsDetails ? 10 : 8),
                                _buildReactions(card),
                                const SizedBox(height: 4),
                                SizedBox(
                                  height: 48,
                                  child: showsDetails
                                      ? null
                                      : _buildSwipeHint(),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                SafeArea(
                  bottom: false,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          IconButton.filled(
                            tooltip: '戻る',
                            style: IconButton.styleFrom(
                              backgroundColor: showsPhotoPrompt
                                  ? Colors.black45
                                  : _colors.control,
                              foregroundColor: showsPhotoPrompt
                                  ? Colors.white
                                  : _colors.ink,
                            ),
                            onPressed: () => _details && !widget.initialDetails
                                ? _showDetails(false)
                                : Navigator.pop(context),
                            icon: const Icon(Icons.arrow_back),
                          ),
                          const Spacer(),
                          // 近くの人を出している時だけ (投稿の案内の画面では何がデモか分からない)
                          if (widget.showPreviewLabels &&
                              widget.isSimulated &&
                              card != null)
                            const _Badge('デモ'),
                          if (widget.showPreviewLabels && card?.isDemo == true)
                            const _Badge('AI 生成'),
                          if (isCurrent &&
                              (widget.onBlock != null ||
                                  widget.onReport != null))
                            IconButton(
                              tooltip: 'ブロック・通報',
                              color: _colors.ink,
                              icon: const Icon(Icons.more_vert),
                              onPressed: _sending
                                  ? null
                                  : () => _openSafetyMenu(card),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _empty(String message, String action, VoidCallback onPressed) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: _colors.ink),
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(onPressed: onPressed, child: Text(action)),
            ],
          ),
        ),
      );

  Widget _noNearbyOutfits() => LayoutBuilder(
    builder: (context, constraints) {
      final center = Offset(
        constraints.maxWidth / 2,
        constraints.maxHeight * 0.39,
      );
      return Stack(
        children: [
          Positioned.fill(
            child: RipplingHanger(center: center, color: _colors.ink),
          ),
          Positioned.fill(
            top: center.dy + 48,
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              Text(
                                '近くのコーデはまだありません',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _colors.ink,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                '近くで公開されたコーデがここに表示されます',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _colors.muted,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      FilledButton.icon(
                        style: _actionButton.copyWith(
                          minimumSize: const WidgetStatePropertyAll(
                            Size(0, 56),
                          ),
                          textStyle: const WidgetStatePropertyAll(
                            TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('再確認'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );

  Widget _buildCardIndicators(NearbyCard card, bool isCurrent) {
    final minutes = card.seenAgoSec ~/ 60;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isCurrent)
          Text(
            minutes < 1 ? 'たった今' : '$minutes分前',
            style: TextStyle(
              color: _colors.ink,
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
          ),
        const SizedBox(height: 4),
        if (_cards.length > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var index = 0; index < _cards.length; index++)
                Semantics(
                  label: '${index + 1}件目',
                  selected: index == _index,
                  button: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _pages.animateToPage(
                      index,
                      duration: const Duration(milliseconds: 230),
                      curve: Curves.easeOut,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 8,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: index == _index
                              ? _colors.ink
                              : _colors.outline,
                          shape: BoxShape.circle,
                        ),
                        child: const SizedBox.square(dimension: 8),
                      ),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildSwipeHint() => Center(
    child: TextButton.icon(
      onPressed: () => _showDetails(true),
      style: TextButton.styleFrom(
        foregroundColor: _colors.muted,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      icon: const Icon(Icons.keyboard_arrow_down),
      label: const Text('下にスワイプで詳細', textAlign: TextAlign.center),
    ),
  );

  Widget _buildReactions(NearbyCard card) {
    final liked = _liked.contains(card.cardId);
    final saved = card.items.any(
      (item) => _saved.containsKey((card.cardId, item.cardItemId)),
    );
    return Row(
      children: [
        if (widget.showLike)
          Expanded(
            child: FilledButton.icon(
              style: _actionButton,
              onPressed: _updatingReaction
                  ? null
                  : () => _toggleLike(card, liked),
              icon: Icon(liked ? Icons.favorite : Icons.favorite_border),
              label: const Text('いいね', textAlign: TextAlign.center),
            ),
          ),
        if (widget.showLike && widget.showSave) const SizedBox(width: 10),
        if (widget.showSave)
          IconButton.filled(
            tooltip: '保存',
            style: IconButton.styleFrom(
              backgroundColor: _colors.ink,
              foregroundColor: _colors.canvas,
              minimumSize: const Size(48, 48),
            ),
            onPressed:
                !card.items.any(
                      (item) => widget.canSaveItem?.call(item) != false,
                    ) ||
                    _updatingReaction
                ? null
                : () => _chooseSavedItem(card),
            icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
          ),
      ],
    );
  }

  Future<void> _toggleLike(NearbyCard card, bool liked) =>
      _updateReaction(() async {
        await widget.onSetLike?.call(card.cardId, !liked);
        if (mounted) {
          if (liked) {
            _liked.remove(card.cardId);
          } else {
            _liked.add(card.cardId);
          }
        }
      });

  Future<void> _chooseSavedItem(NearbyCard card) {
    CardItem? updating;
    return showActionSheet<void>(
      context,
      title: 'アイテムを保存',
      icon: Icons.bookmark_border,
      content: StatefulBuilder(
        builder: (context, setSheetState) => Column(
          children: card.items
              .where((item) => widget.canSaveItem?.call(item) != false)
              .map((item) {
                final saved = _saved.containsKey((
                  card.cardId,
                  item.cardItemId,
                ));
                return Row(
                  children: [
                    Expanded(child: Text(item.label)),
                    const SizedBox(width: 12),
                    IconButton(
                      tooltip: saved
                          ? '${item.label}の保存を解除'
                          : '${item.label}を保存',
                      isSelected: saved,
                      icon: updating == item
                          ? const AppLoadingIndicator(size: 24)
                          : Icon(
                              saved ? Icons.bookmark : Icons.bookmark_border,
                            ),
                      onPressed: updating != null
                          ? null
                          : () async {
                              setSheetState(() => updating = item);
                              await _toggleSave(card, item);
                              if (context.mounted) {
                                setSheetState(() => updating = null);
                              }
                            },
                    ),
                  ],
                );
              })
              .toList(),
        ),
      ),
      actions: const [(value: null, label: '閉じる', destructive: false)],
    );
  }

  Future<void> _toggleSave(NearbyCard card, CardItem item) => _updateReaction(
    () async {
      final key = (card.cardId, item.cardItemId);
      if (_saved[key] case final id?) {
        await widget.onDeleteSave?.call(id);
        if (mounted) _saved.remove(key);
      } else {
        final id = await widget.onSaveItem?.call(card.cardId, item.cardItemId);
        if (mounted) _saved[key] = id ?? item.cardItemId;
      }
    },
  );

  Future<void> _updateReaction(Future<void> Function() action) async {
    if (_updatingReaction) return;
    setState(() => _updatingReaction = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        _message(
          error is ApiException ? error.message : '更新できませんでした',
          icon: Icons.error_outline,
        );
      }
    } finally {
      if (mounted) setState(() => _updatingReaction = false);
    }
  }

  Widget _buildDetails(NearbyCard card) {
    final items = [...card.items]
      ..sort((a, b) => slotOrder(a.slot).compareTo(slotOrder(b.slot)));
    final selected = _selected;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '着用アイテム',
          style: TextStyle(
            color: _colors.ink,
            fontSize: 19,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Text('着用アイテムはありません', style: TextStyle(color: _colors.muted))
        else
          _ItemStrip(
            key: ValueKey(card.cardId),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final active = item == selected;
              return Material(
                color: active ? _colors.outline : _colors.control,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: active
                      ? BorderSide(color: _colors.ink)
                      : BorderSide.none,
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => setState(() => _selected = item),
                  child: SizedBox(
                    width: _ItemStrip.tileWidth,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        children: [
                          Expanded(
                            child: _image(
                              widget.imageFor(item.image),
                              Icons.checkroom_outlined,
                              _colors.muted,
                            ),
                          ),
                          Text(
                            slotLabel(item.slot),
                            style: TextStyle(
                              color: _colors.muted,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            item.label,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _colors.ink,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (item.color.isNotEmpty)
                            Text(
                              item.color,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _colors.muted,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        const SizedBox(height: 12),
        if (selected != null && selected.memo.isNotEmpty) ...[
          Text(selected.memo, style: TextStyle(color: _colors.muted)),
          const SizedBox(height: 8),
        ],
        if (items.isNotEmpty)
          FilledButton.icon(
            style: _actionButton,
            onPressed:
                selected == null ||
                    _matching ||
                    widget.canMatchItem?.call(selected) == false
                ? null
                : widget.onMatch == null
                ? () => _message('手持ちとの照合は準備中です')
                : () => _startMatch(card, selected),
            icon: _matching
                ? const AppLoadingIndicator(size: 24)
                : const Icon(Icons.search),
            label: const Text('手持ちと照合', textAlign: TextAlign.center),
          ),
      ],
    );
  }

  Future<void> _startMatch(NearbyCard card, CardItem item) async {
    setState(() => _matching = true);
    try {
      await widget.onMatch!(card, item);
    } catch (error) {
      if (mounted) {
        _message(
          error is ApiException ? error.message : '照合を始められませんでした',
          icon: Icons.error_outline,
        );
      }
    } finally {
      if (mounted) setState(() => _matching = false);
    }
  }
}

class _ItemStrip extends StatefulWidget {
  const _ItemStrip({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  });

  static const tileWidth = 92.0;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  State<_ItemStrip> createState() => _ItemStripState();
}

class _ItemStripState extends State<_ItemStrip> {
  static const _gap = 8.0;
  final _scroll = ScrollController(keepScrollOffset: false);
  int _currentDot = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients || !_scroll.position.hasContentDimensions) return;
    final max = _scroll.position.maxScrollExtent;
    if (max <= 0) return;
    final progress = (_scroll.offset / max).clamp(0.0, 1.0);
    final dot = (progress * (widget.itemCount - 1)).round();
    if (dot != _currentDot) setState(() => _currentDot = dot);
  }

  void _goToDot(int dot) {
    final target =
        _scroll.position.maxScrollExtent * dot / (widget.itemCount - 1);
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final contentWidth =
          (_ItemStrip.tileWidth + _gap) * widget.itemCount - _gap;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 152,
            child: ListView.separated(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              itemCount: widget.itemCount,
              separatorBuilder: (_, _) => const SizedBox(width: _gap),
              itemBuilder: widget.itemBuilder,
            ),
          ),
          if (contentWidth > constraints.maxWidth && widget.itemCount > 1) ...[
            const SizedBox(height: 4),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var index = 0; index < widget.itemCount; index++)
                    Semantics(
                      label: '着用アイテムのスクロール位置 ${index + 1}',
                      selected: index == _currentDot,
                      button: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _goToDot(index),
                        child: SizedBox(
                          width: 20,
                          height: 24,
                          child: Center(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: index == _currentDot
                                    ? context.palette.ink
                                    : context.palette.outline,
                                shape: BoxShape.circle,
                              ),
                              child: const SizedBox.square(dimension: 8),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      );
    },
  );
}

class _Badge extends StatelessWidget {
  const _Badge(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(left: 6),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: const TextStyle(color: Colors.white, fontSize: 12),
    ),
  );
}

class _OutfitPhoto extends StatelessWidget {
  const _OutfitPhoto({required this.image, required this.details});
  final ImageProvider? image;
  final bool details;

  @override
  Widget build(BuildContext context) {
    final colors = context.palette;
    final photo = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.canvas,
        gradient: colors.isDark
            ? const RadialGradient(
                center: Alignment(0.1, -0.45),
                radius: 1,
                colors: [Color(0xff888680), Color(0xff42413f)],
              )
            : null,
      ),
      child: FractionallySizedBox(
        alignment: const Alignment(0, -0.8),
        widthFactor: 0.9,
        heightFactor: 0.84,
        child: _image(image, Icons.person_outline, colors.muted),
      ),
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(end: details ? 0.43 : 0.70),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOut,
      builder: (context, start, _) => Stack(
        fit: StackFit.expand,
        children: [
          photo,
          ClipRect(
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: const [Colors.transparent, Colors.white],
                stops: [start, start + 0.14],
              ).createShader(bounds),
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: photo,
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, colors.loadingBackground],
                stops: [start, start + 0.26],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _image(ImageProvider? image, IconData fallback, Color fallbackColor) {
  final placeholder = Icon(fallback, color: fallbackColor, size: 30);
  if (image == null) return placeholder;
  return Image(
    image: image,
    fit: BoxFit.contain,
    errorBuilder: (_, _, _) => placeholder,
  );
}
