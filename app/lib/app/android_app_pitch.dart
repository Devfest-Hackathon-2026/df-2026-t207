import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'open_url.dart';

/// 審査員向けの APK の置き場 (Firebase Hosting)。
const apkPath = '/wear-by.apk';

const _ink = Color(0xff1b1b1b);
const _text = Color(0xff2b2925);
const _muted = Color(0xff6b675f);

/// 本命の Android アプリへの誘導。Web デモの外枠の左と、Web デモで「+」を押した時の画面で同じ物を使う。
///
/// [download] を付けると、QR の下に APK を落とすボタンを出す (スマホで開いた人は自分の画面の QR を読めないため)。
class AndroidAppPitch extends StatelessWidget {
  const AndroidAppPitch({super.key, this.download = false});

  final bool download;

  @override
  Widget build(BuildContext context) {
    final apk = Uri.base.resolve(apkPath).toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              // 青山さんのアプリのアイコン (Web の置き場にある物をそのまま使う)
              child: Image.network(
                Uri.base.resolve('icons/Icon-192.png').toString(),
                width: 48,
                height: 48,
                errorBuilder: (_, _, _) =>
                    const SizedBox(width: 48, height: 48),
              ),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Android アプリ',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: _text,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'APK · Google ログイン',
                  style: TextStyle(fontSize: 13, color: _muted),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        // 押せる物に見えないよう、塗った箱ではなく左の線で強調する (押せるのは下の APK のボタンだけ)
        Container(
          padding: const EdgeInsets.only(left: 12),
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: _ink, width: 3)),
          ),
          child: const Text(
            'すべての機能は Android アプリで',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: _text,
            ),
          ),
        ),
        const SizedBox(height: 16),
        // QR を残りの幅で大きくし、説明を右の余白の位置に揃える (左右の余白を同じに見せる)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: QrImageView(data: apk, padding: EdgeInsets.zero),
                ),
              ),
            ),
            const SizedBox(width: 16),
            const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Feature(Icons.bluetooth, 'Bluetooth ですれ違う'),
                SizedBox(height: 12),
                _Feature(Icons.photo_camera_outlined, '自分の服を撮って登録'),
                SizedBox(height: 12),
                _Feature(Icons.checkroom_outlined, '自分の手持ちで照合'),
              ],
            ),
          ],
        ),
        if (download) ...[
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _ink,
              foregroundColor: Colors.white,
            ),
            onPressed: () => openUrl(Uri.base.resolve(apkPath).toString()),
            icon: const Icon(Icons.download, size: 18),
            label: const Text('APK をダウンロード'),
          ),
        ],
      ],
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: _muted),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 14, height: 1.4, color: _text),
        ),
      ],
    );
  }
}

/// Web デモで「+」(投稿) を押した時に開く。投稿は Google ログインのアプリでだけできるので、アプリへ強く誘導する。
Future<void> showAndroidAppSheet(BuildContext context) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.white,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
  ),
  builder: (context) => const SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'コーデの投稿はアプリで',
            // 背景を白に固定しているので、文字の色も固定する (ダークモードで白い文字にならないように)
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: _text,
            ),
          ),
          SizedBox(height: 20),
          AndroidAppPitch(download: true),
        ],
      ),
    ),
  ),
);
