import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../api/api_models.dart';
import '../app/app_banner.dart';
import '../app/app_loading.dart';
import '../app/app_palette.dart';
import '../app/confirmation_sheet.dart';
import 'friend_avatar.dart';
import 'friend_profile_screen.dart';
import 'social_activity.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key, required this.activity});

  final SocialActivity activity;

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  String _query = '';
  bool _busy = false;
  static final _friendCode = RegExp(r'^[A-Z0-9]{8}$');

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        showAppBanner(
          context,
          error is ApiException ? error.message : 'フレンド情報を更新できませんでした',
          icon: Icons.error_outline,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode(String value) async {
    final code = value.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    if (!_friendCode.hasMatch(code)) {
      showAppBanner(context, '8文字のフレンドコードを入力してください');
      return;
    }
    await _run(() async {
      final accepted = await widget.activity.sendRequest(code);
      if (mounted) {
        showAppBanner(
          context,
          accepted ? 'フレンドになりました' : '申請を送りました',
          icon: Icons.check_circle_outline,
        );
      }
    });
  }

  Future<void> _chooseAddOption() async {
    final useCode = await showActionSheet<bool>(
      context,
      title: 'フレンドを追加',
      icon: Icons.person_add_outlined,
      actions: const [
        (value: true, label: 'コードで申請', destructive: false),
        (value: false, label: 'QRを読む', destructive: false),
      ],
    );
    if (!mounted || useCode == null) return;
    if (useCode) {
      await _enterCode();
    } else {
      await _scanCode();
    }
  }

  Future<void> _enterCode() async {
    var code = '';
    final confirmed = await showConfirmationSheet(
      context,
      title: 'フレンドコードを入力',
      icon: Icons.person_add_outlined,
      confirmLabel: '申請する',
      destructive: false,
      content: Builder(
        builder: (fieldContext) => TextField(
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.done,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            hintText: '8文字のフレンドコード',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onChanged: (value) => code = value,
          onSubmitted: (value) {
            code = value;
            Navigator.pop(fieldContext, true);
          },
        ),
      ),
    );
    if (mounted && confirmed == true) await _sendCode(code);
  }

  Future<void> _scanCode() async {
    var found = false;
    final code = await Navigator.of(context, rootNavigator: true).push<String>(
      MaterialPageRoute(
        builder: (page) => Scaffold(
          appBar: AppBar(),
          body: MobileScanner(
            errorBuilder: (_, _) => const Center(child: Text('カメラを使えませんでした')),
            onDetect: (capture) {
              if (found) return;
              for (final barcode in capture.barcodes) {
                final code = barcode.rawValue?.trim().toUpperCase();
                if (barcode.format == BarcodeFormat.qrCode &&
                    code != null &&
                    _friendCode.hasMatch(code)) {
                  found = true;
                  Navigator.pop(page, code);
                  break;
                }
              }
            },
          ),
        ),
      ),
    );
    if (mounted && code != null) await _sendCode(code);
  }

  Future<void> _showMyCode(String code) async {
    final colors = context.palette;
    final qrInk = colors.isDark ? Colors.white : Colors.black;
    final qrBackground = colors.isDark ? Colors.black : Colors.white;
    await showConfirmationSheet(
      context,
      title: '自分のフレンドコード',
      icon: Icons.qr_code_2_rounded,
      confirmLabel: '閉じる',
      cancelLabel: null,
      destructive: false,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: qrBackground,
            shape: RoundedRectangleBorder(
              borderRadius: const BorderRadius.all(Radius.circular(20)),
              side: BorderSide(color: colors.outline),
            ),
            clipBehavior: Clip.antiAlias,
            child: SizedBox.square(
              dimension: 208,
              child: QrImageView(
                data: code,
                padding: const EdgeInsets.all(32),
                semanticsLabel: 'フレンドコードのQR',
                eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.circle, color: qrInk),
                dataModuleStyle: QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.circle,
                  color: qrInk,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SelectableText(
            code,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: 3,
            ),
          ),
        ],
      ),
    );
  }

  void _openProfile(SocialFriend friend) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context)
        .push<void>(FriendProfileScreen.route(friend, widget.activity));
  }

  Future<void> _removeFriend(SocialFriend friend) async {
    final remove = await showConfirmationSheet(
      context,
      title: '${friend.name}をフレンドから削除しますか？',
      icon: Icons.person_outline,
      confirmLabel: '削除',
    );
    if (mounted && remove == true) {
      await _run(() => widget.activity.removeFriend(friend));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.activity,
    builder: (context, _) => _buildList(),
  );

  Widget _buildList() {
    final activity = widget.activity;
    final friends = activity.friends;
    final requests = activity.requests;
    final matchingFriends = friends
        .where((friend) => friend.name.toLowerCase().contains(_query))
        .toList();
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 12, 4),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'フレンド',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
                if (activity.connected) ...[
                  IconButton(
                    tooltip: 'フレンドを追加',
                    icon: const Icon(Icons.add),
                    onPressed: _busy ? null : _chooseAddOption,
                  ),
                  if (activity.friendCode case final code?)
                    IconButton(
                      tooltip: '自分のコード',
                      onPressed: () => _showMyCode(code),
                      icon: const Icon(Icons.share_outlined),
                    ),
                ],
              ],
            ),
          ),
          Expanded(
            child: AppRefreshIndicator(
              onRefresh: () => _run(activity.refreshFriends),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 104),
                children: [
                  TextField(
                    onChanged: (value) =>
                        setState(() => _query = value.trim().toLowerCase()),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: '名前で検索',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: context.palette.control,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (activity.friendsUnavailable)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _run(activity.refreshFriends),
                      child: const Text('フレンド情報を再取得'),
                    ),
                  if (requests.isNotEmpty) ...[
                    _SectionTitle('フレンド申請', '${requests.length}件'),
                    _FriendGroup(
                      children: [
                        for (final friend in requests)
                          _FriendRow(
                            name: friend.name,
                            trailing: _RequestActions(
                              onAccept: _busy
                                  ? null
                                  : () => _run(
                                      () => activity.respondToRequest(
                                        friend,
                                        accept: true,
                                      ),
                                    ),
                              onDecline: _busy
                                  ? null
                                  : () => _run(
                                      () => activity.respondToRequest(
                                        friend,
                                        accept: false,
                                      ),
                                    ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 22),
                  ],
                  if (activity.outgoing.isNotEmpty) ...[
                    _SectionTitle('送信済みの申請', '${activity.outgoing.length}件'),
                    _FriendGroup(
                      children: [
                        for (final request in activity.outgoing)
                          _FriendRow(
                            name: request.name,
                            trailing: TextButton(
                              style: TextButton.styleFrom(
                                foregroundColor: context.palette.danger,
                              ),
                              onPressed: _busy
                                  ? null
                                  : () => _run(
                                      () => activity.cancelRequest(request.id),
                                    ),
                              child: const Text('取り消す'),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 22),
                  ],
                  _SectionTitle('フレンド一覧', '${friends.length}人'),
                  _FriendGroup(
                    children: [
                      if (matchingFriends.isEmpty &&
                          !activity.friendsUnavailable)
                        Padding(
                          padding: const EdgeInsets.all(22),
                          child: Text(
                            friends.isEmpty ? 'フレンドはまだいません' : '該当するフレンドはいません',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: context.palette.muted),
                          ),
                        ),
                      for (final friend in matchingFriends)
                        _FriendRow(
                          key: ValueKey(friend.id),
                          name: friend.name,
                          image: friend.profileImage,
                          crop: friend.profileCrop,
                          onTap: () => _openProfile(friend),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Tooltip(
                                message: '${friend.name}を削除',
                                child: TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _removeFriend(friend),
                                  style: TextButton.styleFrom(
                                    foregroundColor: context.palette.danger,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                    minimumSize: const Size(48, 44),
                                  ),
                                  child: const Text('削除'),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.chevron_right,
                                size: 20,
                                color: context.palette.muted,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label, this.count);

  final String label;
  final String count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
    child: Wrap(
      spacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Semantics(
          header: true,
          child: Text(
            label,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: context.palette.control,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: Text(
              count,
              style: TextStyle(
                color: context.palette.muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _FriendGroup extends StatelessWidget {
  const _FriendGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    color: context.palette.isDark
        ? context.palette.panel
        : context.palette.canvas,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(color: context.palette.outline),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, row) in children.indexed) ...[
          if (index > 0)
            Divider(
              height: 1,
              indent: 64,
              endIndent: 12,
              color: context.palette.outline,
            ),
          row,
        ],
      ],
    ),
  );
}

class _FriendRow extends StatelessWidget {
  const _FriendRow({
    super.key,
    required this.name,
    required this.trailing,
    this.onTap,
    this.image,
    this.crop,
  });

  final String name;
  final Widget trailing;
  final VoidCallback? onTap;
  final ImageProvider? image;
  final String? crop;

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    minTileHeight: 66,
    horizontalTitleGap: 12,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
    leading: FriendAvatar(name: name, image: image, crop: crop),
    title: Text(
      name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontWeight: FontWeight.w700),
    ),
    trailing: trailing,
  );
}

class _RequestActions extends StatelessWidget {
  const _RequestActions({required this.onAccept, required this.onDecline});

  final VoidCallback? onAccept;
  final VoidCallback? onDecline;

  @override
  Widget build(BuildContext context) {
    const size = Size(60, 44);
    const padding = EdgeInsets.symmetric(horizontal: 10);
    const label = TextStyle(fontSize: 13, fontWeight: FontWeight.w700);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton(
          onPressed: onAccept,
          style: FilledButton.styleFrom(
            backgroundColor: context.palette.ink,
            foregroundColor: context.palette.canvas,
            minimumSize: size,
            padding: padding,
            textStyle: label,
          ),
          child: const Text('承認'),
        ),
        const SizedBox(width: 6),
        OutlinedButton(
          onPressed: onDecline,
          style: OutlinedButton.styleFrom(
            foregroundColor: context.palette.ink,
            side: BorderSide(color: context.palette.outline),
            minimumSize: size,
            padding: padding,
            textStyle: label,
          ),
          child: const Text('辞退'),
        ),
      ],
    );
  }
}
