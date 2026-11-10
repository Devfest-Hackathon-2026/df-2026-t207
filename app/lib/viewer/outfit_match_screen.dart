import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/api_models.dart';
import '../app/app_loading.dart';
import '../app/app_palette.dart';
import '../common/outfit_item_tile.dart';
import 'try_on_screen.dart';

class OutfitMatchScreen extends StatefulWidget {
  const OutfitMatchScreen({
    super.key,
    required this.api,
    required this.card,
    required this.item,
  });

  final ApiClient api;
  final NearbyCard card;
  final CardItem item;

  @override
  State<OutfitMatchScreen> createState() => _OutfitMatchScreenState();
}

class _OutfitMatchScreenState extends State<OutfitMatchScreen> {
  late var _match = _loadMatch();
  late final _wardrobe = _loadWardrobe();

  Future<MatchResult> _loadMatch() =>
      widget.api.match(widget.card.cardId, widget.item.cardItemId);

  Future<Map<String, WardrobeItem>> _loadWardrobe() async {
    try {
      return {
        for (final item in await widget.api.getWardrobe()) item.itemId: item,
      };
    } catch (_) {
      // 照合の結果は、クローゼットの画像を取得できない時も表示する。
      return const {};
    }
  }

  void _tryOn(OutfitCombination combo) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => TryOnScreen(
        api: widget.api,
        cardId: widget.card.cardId,
        item: widget.item,
        wardrobeItemIds: combo.wardrobeItemIds,
        wardrobe: _wardrobe,
      ),
    ),
  );

  Widget _items(Iterable<WardrobeItem> items) => Wrap(
    spacing: 10,
    runSpacing: 10,
    children: [
      for (final item in items)
        SizedBox(
          width: 88,
          child: OutfitItemTile(
            label: item.label,
            image: widget.api.image(item.image),
          ),
        ),
    ],
  );

  Widget _selectedItem(AppPalette colors) => _MatchPanel(
    child: Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox.square(
            dimension: 76,
            child: ColoredBox(
              color: colors.control,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Image(
                  image: widget.api.image(widget.item.image),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      Icon(Icons.checkroom_outlined, color: colors.muted),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                slotLabel(widget.item.slot),
                style: TextStyle(fontSize: 12, color: colors.muted),
              ),
              const SizedBox(height: 3),
              Text(
                widget.item.label,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (widget.item.color.isNotEmpty)
                Text(widget.item.color, style: TextStyle(color: colors.muted)),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _error(Object? error, AppPalette colors) => _MatchPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _MatchHeading('照合できませんでした'),
        const SizedBox(height: 6),
        Text(
          error is ApiException ? error.message : 'もう一度お試しください',
          style: TextStyle(color: colors.muted),
        ),
        if (error is! ApiException || error.statusCode != 410) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => setState(() {
              _match = _loadMatch();
            }),
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.ink,
              side: BorderSide(color: colors.outline),
              minimumSize: const Size(0, 48),
              shape: appActionShape,
            ),
            child: const Text('もう一度'),
          ),
        ],
      ],
    ),
  );

  List<Widget> _results(
    MatchResult result,
    Map<String, WardrobeItem> wardrobe,
    AppPalette colors,
  ) => [
    if (result.similarOwned case final similar?) ...[
      _MatchPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _MatchHeading('似た服を持っています'),
            if (wardrobe[similar.itemId] case final item?) ...[
              const SizedBox(height: 12),
              _items([item]),
            ],
          ],
        ),
      ),
      const SizedBox(height: 12),
    ],
    // 事前に作った結果 (AI を止めている時だけ返る) は、組み合わせの有無に関わらずそう出す
    if (result.precomputed)
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          'AI を止めているため、事前に作った結果です',
          style: TextStyle(fontSize: 12, color: colors.muted),
        ),
      ),
    if (result.combos.isEmpty)
      const _MatchPanel(child: _MatchHeading('手持ちに合う物が見つかりません'))
    else ...[
      const _MatchHeading('手持ちで合わせる'),
      const SizedBox(height: 10),
      for (final combo in result.combos)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _MatchPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _items(
                  combo.wardrobeItemIds
                      .map((id) => wardrobe[id])
                      .whereType<WardrobeItem>(),
                ),
                if (combo.reason.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    combo.reason,
                    style: TextStyle(color: colors.muted, height: 1.5),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => _tryOn(combo),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.ink,
                    foregroundColor: colors.canvas,
                    minimumSize: const Size(0, 48),
                    shape: appActionShape,
                  ),
                  child: const Text('着てみる'),
                ),
              ],
            ),
          ),
        ),
    ],
    if (result.missing case final missing? when missing.isNotEmpty)
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: _MatchPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _MatchHeading('足りない1着'),
              const SizedBox(height: 6),
              Text(missing, style: TextStyle(color: colors.muted)),
            ],
          ),
        ),
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.palette;
    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(
        backgroundColor: colors.canvas,
        foregroundColor: colors.ink,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          '手持ちと照合',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        top: false,
        child: FutureBuilder<MatchResult>(
          future: _match,
          builder: (context, snapshot) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _selectedItem(colors),
              const SizedBox(height: 16),
              if (snapshot.connectionState != ConnectionState.done)
                _MatchPanel(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Column(
                      children: [
                        const AppLoadingIndicator(size: 32),
                        const SizedBox(height: 10),
                        Text(
                          '手持ちと照らし合わせています',
                          style: TextStyle(color: colors.muted),
                        ),
                      ],
                    ),
                  ),
                )
              else if (snapshot.data case final result?)
                FutureBuilder<Map<String, WardrobeItem>>(
                  future: _wardrobe,
                  builder: (context, wardrobe) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _results(
                      result,
                      wardrobe.data ?? const {},
                      colors,
                    ),
                  ),
                )
              else
                _error(snapshot.error, colors),
            ],
          ),
        ),
      ),
    );
  }
}

class _MatchPanel extends StatelessWidget {
  const _MatchPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.palette.panel,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: context.palette.outline),
    ),
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );
}

class _MatchHeading extends StatelessWidget {
  const _MatchHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: TextStyle(
      color: context.palette.ink,
      fontSize: 16,
      fontWeight: FontWeight.bold,
    ),
  );
}
