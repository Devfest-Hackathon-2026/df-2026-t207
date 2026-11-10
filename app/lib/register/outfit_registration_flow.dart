import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../app/app_banner.dart';
import '../app/app_loading.dart';
import '../app/app_palette.dart';
import '../capture/outfit_items_review_screen.dart';
import '../capture/outfit_review_background.dart';
import 'outfit_job.dart';

/// 撮った全身写真を登録するまで (A4): vision で処理 → 服を確かめる (S9) → 今日のコーデと手持ちに登録。
///
/// 登録できたら true で閉じる。途中で戻った時と、処理に失敗して撮りなおす時は false。
class OutfitRegistrationFlow extends StatefulWidget {
  const OutfitRegistrationFlow({
    super.key,
    required this.api,
    required this.jobs,
    required this.uid,
    required this.photo,
  });

  final ApiClient api;
  final OutfitJobSource jobs;
  final Future<String> Function() uid;
  final Uint8List photo;

  @override
  State<OutfitRegistrationFlow> createState() => _OutfitRegistrationFlowState();
}

class _OutfitRegistrationFlowState extends State<OutfitRegistrationFlow> {
  OutfitJob? _progress;
  String? _error;
  String? _jobId;
  OutfitJob? _result;
  List<OutfitReviewItem> _items = const [];
  final Map<int, String> _memos = {};
  bool _registering = false;

  @override
  void initState() {
    super.initState();
    _process();
  }

  Future<void> _process() async {
    setState(() {
      _progress = null;
      _error = null;
    });
    try {
      final uid = await widget.uid();
      final done = await runOutfitJob(
        api: widget.api,
        jobs: widget.jobs,
        uid: uid,
        photo: widget.photo,
        onProgress: (job) {
          if (mounted) setState(() => _progress = job);
        },
      );
      if (!mounted) return;
      setState(() {
        _jobId = done.jobId;
        _result = done.job;
        _items = [
          for (final item in done.job.items)
            OutfitReviewItem(
              index: item.index,
              label: item.label,
              slot: item.slot,
              image: widget.api.image(item.image),
            ),
        ];
      });
    } on OutfitJobException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '処理に失敗しました。通信を確かめて、もう一度お試しください');
    }
  }

  Future<void> _register() async {
    final jobId = _jobId;
    if (jobId == null || _items.isEmpty || _registering) return;
    setState(() => _registering = true);
    try {
      await widget.api.registerTodayOutfit(jobId, [
        for (final item in _items) (index: item.index, memo: _memos[item.index] ?? ''),
      ]);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _registering = false);
      showAppBanner(
        context,
        '投稿できませんでした。もう一度お試しください',
        icon: Icons.error_outline,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    if (result != null) {
      return OutfitItemsReviewScreen(
        outfitImage: result.outfitImage == null ? null : widget.api.image(result.outfitImage!),
        items: _items,
        onRemove: (index) => setState(() {
          _items = _items.where((item) => item.index != index).toList();
        }),
        onMemoChanged: (index, memo) => _memos[index] = memo,
        onAdd: () => showAppBanner(context, '見つからなかった服は、撮りなおすと見つかることがあります'),
        onContinue: _items.isEmpty || _registering ? null : _register,
        continueLabel: _registering ? '投稿しています' : '投稿する',
      );
    }
    return _ProcessingView(
      photo: widget.photo,
      job: _progress,
      error: _error,
      onRetry: _process,
      onRetake: () => Navigator.of(context).pop(false),
    );
  }
}

class _ProcessingView extends StatelessWidget {
  const _ProcessingView({
    required this.photo,
    required this.job,
    required this.error,
    required this.onRetry,
    required this.onRetake,
  });

  final Uint8List photo;
  final OutfitJob? job;
  final String? error;
  final VoidCallback onRetry;
  final VoidCallback onRetake;

  @override
  Widget build(BuildContext context) {
    final error = this.error;
    final colors = context.palette;
    final whiteLoading = error == null && !colors.isDark;
    final foreground = whiteLoading ? colors.ink : Colors.white;
    const white = TextStyle(color: Colors.white);
    return Scaffold(
      backgroundColor: whiteLoading
          ? colors.loadingBackground
          : const Color(0xff242424),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (!whiteLoading) ...[
            OutfitReviewBackground(photoBytes: photo),
            const ColoredBox(color: Color(0x99000000)),
          ],
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      tooltip: '戻る',
                      color: foreground,
                      onPressed: onRetake,
                      icon: const Icon(Icons.arrow_back),
                    ),
                  ),
                  const Spacer(),
                  if (error == null) ...[
                    Text(
                      job?.stepLabel ?? '写真を送っています',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: AppLoadingIndicator(size: 32, color: foreground),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '顔と背景を消してから、服を読み取ります。20 秒ほど (はじめは 2 分ほど) かかります',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: whiteLoading ? colors.muted : Colors.white70,
                      ),
                    ),
                  ] else ...[
                    const Icon(Icons.error_outline, color: Colors.white, size: 40),
                    const SizedBox(height: 12),
                    Text(
                      error,
                      textAlign: TextAlign.center,
                      style: white.copyWith(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: FilledButton(
                              onPressed: onRetake,
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xff222222),
                              ),
                              child: const Text('撮りなおす'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: OutlinedButton(
                              onPressed: onRetry,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white70),
                              ),
                              child: const Text('もう一度送る'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const Spacer(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
