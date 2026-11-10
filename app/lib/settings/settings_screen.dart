import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app/app_banner.dart';
import '../app/app_loading.dart';
import '../app/app_palette.dart';
import '../app/confirmation_sheet.dart';
import '../mypage/my_page_screen.dart';
import '../mypage/profile_photo.dart';
import 'profile_photo_crop_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.displayName,
    required this.isPublishing,
    required this.photo,
    required this.onSaveName,
    required this.onSavePhoto,
    required this.onLogout,
    required this.onDarkModeChanged,
    this.photoLoad,
    this.fallbackPhoto,
    this.focusName = false,
    this.demoMode,
  });

  final String displayName;
  final bool isPublishing;
  final ProfilePhoto? photo;
  final Future<ProfilePhoto?>? photoLoad;
  final ImageProvider? fallbackPhoto;
  final Future<void> Function(String) onSaveName;
  final Future<void> Function(ProfilePhoto?) onSavePhoto;
  final Future<void> Function() onLogout;
  final Future<void> Function(bool) onDarkModeChanged;
  final bool focusName;

  /// デモモード (lib/app/demo_mode.dart)。渡した時だけスイッチを出す
  final ValueNotifier<bool>? demoMode;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _maxPhotoBytes = 2 * 1024 * 1024;
  static const _heading = TextStyle(fontSize: 16, fontWeight: FontWeight.bold);

  late final _name = TextEditingController(text: widget.displayName);
  late String _savedName = widget.displayName;
  late ProfilePhoto? _photo = widget.photo;
  late bool _loadingPhoto = widget.photoLoad != null;
  bool _busy = false;

  bool get _canSaveName {
    final value = _name.text.trim();
    return !_busy &&
        value.isNotEmpty &&
        value.runes.length <= 20 &&
        value != _savedName;
  }

  @override
  void initState() {
    super.initState();
    widget.photoLoad?.then((photo) {
      if (!mounted) return;
      setState(() {
        _photo = photo;
        _loadingPhoto = false;
      });
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _message(String text, {IconData icon = Icons.info_outline}) {
    if (!mounted) return;
    showAppBanner(context, text, icon: icon);
  }

  Future<void> _run(Future<void> Function() action, String failure) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      _message(failure, icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choosePhoto() => _run(() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final selected = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 80,
      requestFullMetadata: false,
    );
    if (!mounted || selected == null) return;
    if (await selected.length() > _maxPhotoBytes) {
      _message('2 MB 以下の画像を選んでください');
      return;
    }
    final bytes = await selected.readAsBytes();
    if (mounted) await _cropAndSave(ProfilePhoto(bytes));
  }, '画像を設定できませんでした');

  Future<void> _cropAndSave(ProfilePhoto photo) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final edited = await Navigator.of(context).push<ProfilePhoto>(
      MaterialPageRoute(
        builder: (_) => ProfilePhotoCropScreen(
          photo: photo,
          previewBuilder: _buildHeaderPreview,
        ),
      ),
    );
    if (!mounted || edited == null) return;
    await widget.onSavePhoto(edited);
    if (mounted) setState(() => _photo = edited);
  }

  Future<void> _clearPhoto() => _run(() async {
    await widget.onSavePhoto(null);
    if (mounted) setState(() => _photo = null);
  }, '画像を削除できませんでした');

  Future<void> _saveName() async {
    if (!_canSaveName) return;
    final value = _name.text.trim();
    FocusScope.of(context).unfocus();
    await _run(() async {
      await widget.onSaveName(value);
      if (!mounted) return;
      _name.text = value;
      setState(() => _savedName = value);
      _message('表示名を変更しました', icon: Icons.check_circle_outline);
    }, '表示名を変更できませんでした');
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showConfirmationSheet(
      context,
      title: 'ログアウトしますか？',
      icon: Icons.logout,
      confirmLabel: 'ログアウト',
    );
    if (!mounted || confirmed != true) return;
    await _run(() async {
      await widget.onLogout();
      if (mounted) Navigator.pop(context);
    }, 'ログアウトできませんでした。もう一度お試しください');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.palette;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: colors.canvas,
        appBar: AppBar(
          backgroundColor: colors.canvas,
          surfaceTintColor: Colors.transparent,
          leadingWidth: 64,
          titleSpacing: 4,
          leading: Padding(
            padding: const EdgeInsets.only(left: 12, right: 8),
            child: Center(
              child: IconButton(
                tooltip: '戻る',
                onPressed: _busy ? null : () => Navigator.maybePop(context),
                icon: const Icon(Icons.arrow_back, size: 21),
                style: IconButton.styleFrom(
                  backgroundColor: colors.control,
                  foregroundColor: colors.ink,
                ),
              ),
            ),
          ),
          // 日本語の見出しは ← より下に見えるので、行の高さを字の大きさにして少し持ち上げて揃える
          title: Transform.translate(
            offset: const Offset(0, -1),
            child: const Text(
              '設定',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                height: 1,
              ),
            ),
          ),
          actions: [
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(right: 16),
                child: Center(child: AppLoadingIndicator()),
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          left: false,
          right: false,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            children: [
              _buildPhotoSection(colors),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildNameSection(colors),
                    const SizedBox(height: 24),
                    Material(
                      color: colors.panel,
                      borderRadius: BorderRadius.circular(18),
                      clipBehavior: Clip.antiAlias,
                      child: SwitchListTile(
                        value: colors.isDark,
                        onChanged: _busy
                            ? null
                            : (enabled) => _run(
                                () => widget.onDarkModeChanged(enabled),
                                '表示テーマを変更できませんでした',
                              ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                        ),
                        secondary: _settingIcon(
                          colors,
                          Icons.dark_mode_outlined,
                          colors.ink,
                        ),
                        title: const Text('ダークモード', style: _heading),
                      ),
                    ),
                    if (widget.demoMode case final demoMode?) ...[
                      const SizedBox(height: 10),
                      Material(
                        color: colors.panel,
                        borderRadius: BorderRadius.circular(18),
                        clipBehavior: Clip.antiAlias,
                        child: ValueListenableBuilder<bool>(
                          valueListenable: demoMode,
                          builder: (context, enabled, _) => SwitchListTile(
                            value: enabled,
                            onChanged: (value) => demoMode.value = value,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                            ),
                            secondary: _settingIcon(
                              colors,
                              Icons.people_outline,
                              colors.ink,
                            ),
                            title: const Text('デモモード', style: _heading),
                            subtitle: const Text('近くの人の代わりに AI 生成の人物を表示'),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Material(
                      color: colors.panel,
                      borderRadius: BorderRadius.circular(18),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        onTap: _busy ? null : _confirmLogout,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                        ),
                        leading: _settingIcon(
                          colors,
                          Icons.logout,
                          colors.danger,
                        ),
                        title: Text(
                          'ログアウト',
                          style: _heading.copyWith(color: colors.danger),
                        ),
                        trailing: Icon(
                          Icons.chevron_right,
                          color: colors.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoSection(AppPalette colors) {
    final photo = _photo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('マイページの画像', style: _heading),
        ),
        const SizedBox(height: 10),
        Semantics(
          label: 'マイページのプレビュー',
          child: _buildHeaderPreview(
            photo,
            MyPageHeader.previewTopInsetOf(context),
          ),
        ),
        _buildPhotoActions(colors, photo),
      ],
    );
  }

  Widget _buildPhotoActions(AppPalette colors, ProfilePhoto? photo) {
    const gap = 8.0;
    const fontSize = 13.0;
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 64)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold),
      ),
    );
    final actions = [
      FilledButton(
        onPressed: _busy || _loadingPhoto ? null : _choosePhoto,
        style: FilledButton.styleFrom(
          backgroundColor: colors.ink,
          foregroundColor: colors.canvas,
        ).merge(style),
        child: _photoActionLabel(
          Icons.photo_library_outlined,
          photo == null ? '画像を選ぶ' : '画像を変更',
        ),
      ),
      if (photo != null) ...[
        FilledButton.tonal(
          onPressed: _busy
              ? null
              : () => _run(() => _cropAndSave(photo), '表示範囲を保存できませんでした'),
          style: FilledButton.styleFrom(
            backgroundColor: colors.control,
            foregroundColor: colors.ink,
          ).merge(style),
          child: _photoActionLabel(Icons.crop, '表示範囲を調整'),
        ),
        FilledButton(
          onPressed: _busy ? null : _clearPhoto,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xffb3261e),
            foregroundColor: Colors.white,
          ).merge(style),
          child: _photoActionLabel(Icons.delete_outline, '画像を削除'),
        ),
      ],
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // いちばん長いラベルが入る幅を基準に、狭い画面では折り返す。
          final minWidth =
              MediaQuery.textScalerOf(context).scale(fontSize) * 7 + 12;
          final columns = ((constraints.maxWidth + gap) / (minWidth + gap))
              .floor()
              .clamp(1, actions.length);
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final action in actions)
                SizedBox(width: width, child: action),
            ],
          );
        },
      ),
    );
  }

  Widget _photoActionLabel(IconData icon, String label) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 20),
      const SizedBox(height: 4),
      Text(label, textAlign: TextAlign.center),
    ],
  );

  Widget _buildHeaderPreview(ProfilePhoto? photo, double topInset) =>
      ExcludeSemantics(
        child: IgnorePointer(
          child: MyPageHeader(
            displayName: _savedName,
            image: widget.fallbackPhoto,
            profilePhoto: photo,
            topInsetOverride: topInset,
            isPublishing: widget.isPublishing,
            onEditName: () {},
            onSettingsPressed: () {},
            onPublishChanged: (_) {},
          ),
        ),
      );

  Widget _buildNameSection(AppPalette colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('表示名', style: _heading),
        const SizedBox(height: 10),
        TextField(
          controller: _name,
          autofocus: widget.focusName,
          enabled: !_busy,
          maxLength: 20,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _saveName(),
          decoration: InputDecoration(
            hintText: '表示名を入力',
            prefixIcon: const Icon(Icons.person_outline),
            filled: true,
            fillColor: colors.control,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        FilledButton(
          onPressed: _canSaveName ? _saveName : null,
          style: FilledButton.styleFrom(
            backgroundColor: colors.ink,
            foregroundColor: colors.canvas,
            minimumSize: const Size(0, 46),
          ),
          child: const Text('表示名を保存'),
        ),
      ],
    );
  }

  Widget _settingIcon(AppPalette colors, IconData icon, Color foreground) =>
      CircleAvatar(
        backgroundColor: colors.canvas,
        foregroundColor: foreground,
        child: Icon(icon, size: 20),
      );
}
