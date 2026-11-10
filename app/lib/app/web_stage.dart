import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api/api_models.dart';
import 'android_app_pitch.dart';

/// PC の広い画面で開いた Web デモの外枠。
///
/// 左に説明 (本命は Android アプリ)、中央に操作するあなた (見る側 B) のスマホ、右に「すれ違った人 A」のスマホを並べる。
/// A は動かない見本ではなく、B が今見ているカードの着姿を出し、B のいいねを通知として受ける。
/// A を別のログインにしないのは、匿名の人が A として振る舞える口をサーバに作らないため。
/// これより狭い画面 (スマホで開いた時) は、今までどおりアプリを全画面で出す。
const stageMinWidth = 1000.0;

const _phoneB = Size(390, 844);
const _phoneA = Size(312, 676); // B の 8 割。脇役なので一段小さく

/// 画面の上の時刻の帯と、下のホームの帯。アプリの中身を角丸にかぶせないため、中身はこの間に置く
const _statusBar = 36.0;
const _homeBar = 20.0;

/// 台紙。窓に合わせて縮めるので、縦の余白を詰めてスマホを大きく見せる
const _canvas = Size(1400, 924);

const _ink = Color(0xff1b1b1b);
const _text = Color(0xff2b2925);
const _muted = Color(0xff6b675f);

/// 「発信中」の印。A の画面と、A から B への点線で同じ色を使う
const _live = Color(0xff2e7d4f);

/// 窓の幅 (外枠の中の MediaQuery ではなく) で、外枠を出すかを決める。
bool showsStage(BuildContext context) {
  final view = View.of(context);
  return kIsWeb &&
      view.physicalSize.width / view.devicePixelRatio >= stageMinWidth;
}

class StageState {
  const StageState({this.cardId, this.outfit, this.liked = false});

  final String? cardId;
  final ImageProvider? outfit;
  final bool liked;
}

/// B の画面から A の画面への知らせ。聞いているのは Web の外枠だけ。
final stage = ValueNotifier(const StageState());

/// B が見ているカードが替わった時。
void stageShow(NearbyCard card, ImageProvider? outfit) {
  if (stage.value.cardId == card.cardId) return;
  stage.value = StageState(cardId: card.cardId, outfit: outfit);
}

/// B がカードにいいねを付けた / 外した時。今 A に出ているカードの時だけ届く。
void stageLike(String cardId, bool liked) {
  if (stage.value.cardId != cardId) return;
  stage.value = StageState(
    cardId: cardId,
    outfit: stage.value.outfit,
    liked: liked,
  );
}

class WebStage extends StatelessWidget {
  const WebStage({super.key, required this.child, this.enabled});

  final Widget child;

  /// 試験で外枠を出す / 出さないを決める時だけ渡す。省くと窓の幅で決める
  final bool? enabled;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (!(enabled ?? showsStage(context))) return child;
    return Material(
      color: const Color(0xffe9e7e2),
      child: Center(
        child: FittedBox(
          child: SizedBox.fromSize(
            size: _canvas,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(width: 380, child: _Guide()),
                const SizedBox(width: 80),
                _Phone(
                  label: 'あなた',
                  primary: true,
                  size: _phoneB,
                  child: MediaQuery(
                    data: media.copyWith(
                      size: Size(
                        _phoneB.width,
                        _phoneB.height - _statusBar - _homeBar,
                      ),
                      padding: EdgeInsets.zero,
                      viewPadding: EdgeInsets.zero,
                      viewInsets: EdgeInsets.zero,
                    ),
                    child: child,
                  ),
                ),
                const SizedBox(width: 16),
                const _Signal(),
                const SizedBox(width: 16),
                const _Phone(
                  label: 'すれ違った人',
                  primary: false,
                  size: _phoneA,
                  child: _PersonA(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Phone extends StatelessWidget {
  const _Phone({
    required this.label,
    required this.primary,
    required this.size,
    required this.child,
  });

  final String label;
  final bool primary;
  final Size size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: primary ? FontWeight.w600 : FontWeight.w400,
            color: primary ? _text : _muted,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _ink,
            borderRadius: BorderRadius.circular(48),
            boxShadow: [
              BoxShadow(
                color: Color(primary ? 0x33000000 : 0x1f000000),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(38),
            child: SizedBox.fromSize(
              size: size,
              child: ColoredBox(
                color: Colors.white,
                child: Column(
                  children: [
                    const _StatusBar(),
                    Expanded(child: ClipRect(child: child)),
                    const SizedBox(
                      height: _homeBar,
                      child: Center(child: _HomeIndicator()),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A から B へ、ポケットの中の発信が届く点線 (この作品の印)。
class _Signal extends StatelessWidget {
  const _Signal();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < 6; i++)
          Container(
            width: 4,
            height: 4,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: _live.withValues(alpha: 0.35 + i * 0.1),
              shape: BoxShape.circle,
            ),
          ),
      ],
    );
  }
}

class _Guide extends StatelessWidget {
  const _Guide();

  @override
  Widget build(BuildContext context) {
    const body = TextStyle(fontSize: 15, height: 1.6, color: _text);
    const muted = TextStyle(fontSize: 13, height: 1.5, color: _muted);
    const heading = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: _muted,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Image.asset(
          'assets/images/wearby_wordmark.png',
          height: 40,
          semanticLabel: 'WEARBY',
          // ロゴの画像は白抜き (アプリの暗い帯の上に置く物) なので、明るい外枠では黒く塗る
          color: _ink,
          colorBlendMode: BlendMode.srcIn,
        ),
        const SizedBox(height: 12),
        const Text(
          'すれ違った人の服を、話しかけずに知り、手持ちで合うかまで確かめる',
          style: TextStyle(fontSize: 16, height: 1.6, color: _text),
        ),
        const SizedBox(height: 32),
        const _AndroidCard(),
        const SizedBox(height: 32),
        const Text('この画面で試す', style: heading),
        const SizedBox(height: 12),
        for (final (n, text) in const [
          ('1', '「探す」で、近くにいる人の今日のコーデを見る'),
          ('2', '下にスワイプして、気になる服を選ぶ'),
          ('3', '手持ちと照合し、「着てみる」で着用イメージ'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    n,
                    style: body.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(child: Text(text, style: body)),
              ],
            ),
          ),
        const SizedBox(height: 8),
        const Text('デモモード: 近くの人は AI 生成の架空の人物です', style: muted),
      ],
    );
  }
}

/// 本命の Android アプリ (説明の一番上の白い区画)。中身は「+」の画面と同じ部品
class _AndroidCard extends StatelessWidget {
  const _AndroidCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x14000000)),
      ),
      child: const AndroidAppPitch(),
    );
  }
}

class _PersonA extends StatelessWidget {
  const _PersonA();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xfff6f5f2),
      child: ValueListenableBuilder(
        valueListenable: stage,
        builder: (context, s, _) => Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    '今日のコーデ',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 4),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Icon(Icons.circle, size: 8, color: _live),
                      SizedBox(width: 6),
                      Text(
                        '公開中 · 発信しています',
                        style: TextStyle(fontSize: 12, color: _muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: s.outfit == null
                          ? const Center(
                              child: Text(
                                'まだすれ違っていません',
                                style: TextStyle(fontSize: 13, color: _muted),
                              ),
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image(
                                image: s.outfit!,
                                fit: BoxFit.contain,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              left: 12,
              right: 12,
              top: s.liked ? 12 : -80,
              child: Material(
                color: _ink,
                borderRadius: BorderRadius.circular(14),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.favorite, size: 16, color: Colors.white),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '近くの人からいいねが付きました',
                          style: TextStyle(fontSize: 13, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 実機のような時刻と電池の帯 (見た目だけ)。
class _StatusBar extends StatelessWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: _ink,
    );
    return const SizedBox(
      height: _statusBar,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 28),
        child: Row(
          children: [
            Text('9:41', style: style),
            Spacer(),
            Icon(Icons.signal_cellular_alt, size: 15, color: _ink),
            SizedBox(width: 4),
            Icon(Icons.wifi, size: 15, color: _ink),
            SizedBox(width: 4),
            Icon(Icons.battery_full, size: 15, color: _ink),
          ],
        ),
      ),
    );
  }
}

class _HomeIndicator extends StatelessWidget {
  const _HomeIndicator();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 5,
      decoration: BoxDecoration(
        color: _ink,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}
