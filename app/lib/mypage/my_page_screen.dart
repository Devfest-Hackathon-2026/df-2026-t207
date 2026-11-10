import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../app/app_banner.dart';
import '../app/app_loading.dart';
import '../app/app_palette.dart';
import '../app/confirmation_sheet.dart';
import 'profile_photo.dart';

const _shortcutTopGap = 14.0;
const _shortcutHeight = 52.0;
const _calendarTopGap = 12.0;
const myPageBackgroundColor = Color(0xfff6f2fd);

/// マイページ (仕様書の S12)。今日の公開の切り替えとコーデの表示。
///
/// 公開は初期オフで、その日の 24 時に自動で切れる (設計で決定)。
class MyPageScreen extends StatefulWidget {
  const MyPageScreen({
    super.key,
    required this.displayName,
    required this.isPublishing,
    required this.onPublishChanged,
    required this.onClosetPressed,
    required this.onEditName,
    required this.onSettingsPressed,
    this.headerImage,
    this.profilePhoto,
    this.onSavedPressed,
    this.calendarImages = const {},
    this.onCalendarDayPressed,
    this.onCalendarMonthChanged,
    this.postCount,
    this.streakDays,
    this.friendCount,
    this.closetCount,
    this.notice,
    this.bottomPadding = 104,
  });

  final String displayName;

  /// 上の帯に出す自分の今日の着姿 (頭と背景を消した物)。無ければ無地。
  final ImageProvider? headerImage;
  final ProfilePhoto? profilePhoto;
  final VoidCallback? onSavedPressed;

  /// 各日のコーデ画像。キーは日本時間の日付を表す UTC の年月日。
  final Map<DateTime, ImageProvider> calendarImages;
  final ValueChanged<DateTime>? onCalendarDayPressed;

  /// カレンダーで見ている月が変わった時 (その月の 1 日)。記録は月ごとに読む
  final ValueChanged<DateTime>? onCalendarMonthChanged;

  /// 未取得の件数は null。
  final int? postCount;
  final int? streakDays;
  final int? friendCount;

  final bool isPublishing;

  /// 手持ちの件数。分からない時は null。
  final int? closetCount;

  /// 公開の下に出す注意 (例 Bluetooth がオフ)。無ければ null
  final String? notice;

  /// 公開の切り替え。失敗した時は例外を投げると、画面に出して元に戻す。
  final Future<void> Function(bool publish) onPublishChanged;
  final VoidCallback onClosetPressed;
  final VoidCallback onEditName;
  final VoidCallback onSettingsPressed;

  /// 下に重なるメニューの分の余白。
  final double bottomPadding;

  @override
  State<MyPageScreen> createState() => _MyPageScreenState();
}

class _MyPageScreenState extends State<MyPageScreen> {
  bool _switching = false;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  void _changeMonth(int offset) {
    setState(() => _month = DateTime(_month.year, _month.month + offset));
    widget.onCalendarMonthChanged?.call(_month);
  }

  void _showSavedUnavailable() {
    showAppBanner(context, '保存したアイテムはまだ利用できません');
  }

  Future<void> _toggle(bool value) async {
    if (_switching) return;
    setState(() {
      _switching = true;
    });
    try {
      await widget.onPublishChanged(value);
    } catch (_) {
      if (mounted) {
        showAppBanner(
          context,
          '切り替えられませんでした。もう一度お試しください。',
          icon: Icons.error_outline,
        );
      }
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.isDark
          ? context.palette.canvas
          : myPageBackgroundColor,
      body: ListView(
        padding: EdgeInsets.only(bottom: widget.bottomPadding),
        children: [
          MyPageHeader(
            displayName: widget.displayName,
            image: widget.headerImage,
            profilePhoto: widget.profilePhoto,
            onEditName: widget.onEditName,
            onSettingsPressed: widget.onSettingsPressed,
            isPublishing: widget.isPublishing,
            switching: _switching,
            onPublishChanged: _toggle,
            postCount: widget.postCount,
            streakDays: widget.streakDays,
            friendCount: widget.friendCount,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, _shortcutTopGap, 10, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _ShortcutButton(
                        icon: Icons.bookmark_border,
                        label: '保存したアイテム',
                        onPressed:
                            widget.onSavedPressed ?? _showSavedUnavailable,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ShortcutButton(
                        icon: Icons.checkroom_outlined,
                        label: 'クローゼット',
                        count: widget.closetCount,
                        onPressed: widget.onClosetPressed,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: _calendarTopGap),
                _OutfitCalendar(
                  month: _month,
                  images: widget.calendarImages,
                  bottomPadding: widget.bottomPadding,
                  onChangeMonth: _changeMonth,
                  onDayPressed: widget.onCalendarDayPressed,
                ),
                const SizedBox(height: 12),
                if (widget.notice != null && widget.isPublishing)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      widget.notice!,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 自分とフレンドのマイページで共通のヘッダー。
class MyPageHeader extends StatelessWidget {
  const MyPageHeader({
    super.key,
    required this.displayName,
    this.image,
    this.profilePhoto,
    this.remoteProfileImage,
    this.remoteProfileCrop,
    this.topInsetOverride,
    this.showTitle = true,
    this.onEditName,
    this.onSettingsPressed,
    this.isPublishing = false,
    this.switching = false,
    this.onPublishChanged,
    this.showFriendCount = true,
    this.collapse,
    this.postCount,
    this.streakDays,
    this.friendCount,
  });

  final String displayName;
  final ImageProvider? image;
  final ProfilePhoto? profilePhoto;
  final ImageProvider? remoteProfileImage;
  final String? remoteProfileCrop;
  final double? topInsetOverride;
  final bool isPublishing;
  final bool switching;
  final bool showFriendCount;
  final bool showTitle;
  final double? collapse;
  final ValueChanged<bool>? onPublishChanged;
  final int? postCount;
  final int? streakDays;
  final int? friendCount;
  final VoidCallback? onEditName;
  final VoidCallback? onSettingsPressed;

  static const expandedHeight = 276.0;
  static const compactHeight = 116.0;

  static double previewTopInsetOf(BuildContext context) =>
      kIsWeb ? 0 : MediaQuery.viewPaddingOf(context).top;

  @override
  Widget build(BuildContext context) {
    final topInset = topInsetOverride ?? MediaQuery.paddingOf(context).top;
    final progress = collapse ?? 0.0;
    final name = ConstrainedBox(
      constraints: BoxConstraints(minHeight: lerpDouble(48, 32, progress)!),
      child: Row(
        children: [
          Flexible(
            child: Text(
              displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: lerpDouble(22, 18, progress),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (onEditName != null)
            IconButton(
              onPressed: onEditName,
              tooltip: '名前を変える',
              icon: const Icon(
                Icons.edit_outlined,
                size: 18,
                color: Colors.white,
              ),
            ),
        ],
      ),
    );
    final stats = Row(
      children: [
        _ProfileStat(label: '投稿数', value: postCount, unit: '件'),
        const SizedBox(width: 22),
        _ProfileStat(label: '連続記録', value: streakDays, unit: '日'),
      ],
    );
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
      child: SizedBox(
        height: expandedHeight + topInset,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (profilePhoto case final photo?)
              ProfilePhotoImage(photo: photo)
            else if (remoteProfileImage case final remote?)
              CroppedProfileImage.remote(remote, remoteProfileCrop)
            else if (image == null)
              const ColoredBox(color: Color(0xff3a3a36))
            else
              Image(
                image: image!,
                fit: BoxFit.cover,
                alignment: Alignment(0, -1 + progress * 0.6),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x66000000),
                    Color(0x22000000),
                    Color(0xcc141414),
                  ],
                  stops: [0, 0.45, 1],
                ),
              ),
            ),
            if (showTitle)
              Positioned(
                top: topInset + 8,
                left: 20,
                right: 8,
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'マイページ',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (onSettingsPressed != null)
                      IconButton(
                        onPressed: onSettingsPressed,
                        tooltip: '設定',
                        icon: const Icon(
                          Icons.settings_outlined,
                          color: Colors.white,
                        ),
                      ),
                  ],
                ),
              ),
            if (collapse != null)
              Positioned.fill(
                top: topInset,
                left: 20,
                right: 20,
                bottom: 12,
                child: Align(
                  alignment: Alignment(-1, lerpDouble(-0.25, 1, progress)!),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [name, const SizedBox(height: 7), stats],
                  ),
                ),
              )
            else
              Positioned(left: 20, right: 20, top: topInset + 65, child: name),
            if (showFriendCount)
              Positioned(
                top: topInset + 112,
                left: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white70),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    friendCount == null ? 'フレンド —' : 'フレンド $friendCount人',
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ),
            if (collapse == null)
              Positioned(
                top: topInset + (showFriendCount ? 150 : 120),
                left: 20,
                right: 20,
                child: stats,
              ),
            if (onPublishChanged case final onPublishChanged?)
              Positioned(
                left: 20,
                right: 24,
                bottom: 14,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: switching
                        ? null
                        : () async {
                            final confirmed = await showConfirmationSheet(
                              context,
                              title: isPublishing
                                  ? '今日のコーデを非公開にしますか？'
                                  : '今日のコーデを公開しますか？',
                              icon: isPublishing
                                  ? Icons.lock_outline
                                  : Icons.public_outlined,
                              confirmLabel: isPublishing
                                  ? '非公開にする'
                                  : '近くのユーザーに公開',
                              destructive: false,
                            );
                            if (context.mounted && confirmed == true) {
                              onPublishChanged(!isPublishing);
                            }
                          },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.public_outlined,
                            size: 18,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 6),
                          const Expanded(
                            child: Text(
                              '公開設定',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (switching)
                            const AppLoadingIndicator(color: Colors.white)
                          else
                            Text(
                              isPublishing ? '近くに公開中' : '非公開',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
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

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({
    required this.label,
    required this.value,
    required this.unit,
  });
  final String label;
  final int? value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
        const SizedBox(height: 2),
        Text(
          value == null ? '—' : '$value$unit',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _ShortcutButton extends StatelessWidget {
  const _ShortcutButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.count,
  });

  final IconData icon;
  final String label;
  final int? count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xff232321),
      shape: appActionShape,
      child: InkWell(
        onTap: onPressed,
        customBorder: appActionShape,
        child: Container(
          constraints: const BoxConstraints(minHeight: _shortcutHeight),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    height: 1,
                  ),
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 4),
                Text(
                  '$count 点',
                  style: const TextStyle(
                    color: Color(0xffd6d6d1),
                    fontSize: 11,
                    height: 1,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OutfitCalendar extends StatelessWidget {
  const _OutfitCalendar({
    required this.month,
    required this.images,
    required this.bottomPadding,
    required this.onChangeMonth,
    required this.onDayPressed,
  });
  final DateTime month;
  final Map<DateTime, ImageProvider> images;
  final double bottomPadding;
  final ValueChanged<int> onChangeMonth;
  final ValueChanged<DateTime>? onDayPressed;

  @override
  Widget build(BuildContext context) {
    final firstWeekday = DateTime(month.year, month.month, 1).weekday % 7;
    final days = DateTime(month.year, month.month + 1, 0).day;
    final weeks = ((firstWeekday + days) / 7).ceil();
    final screen = MediaQuery.sizeOf(context);
    final inset = MediaQuery.paddingOf(context).top;
    final spaceAboveCalendar =
        inset +
        MyPageHeader.expandedHeight +
        _shortcutTopGap +
        _shortcutHeight +
        _calendarTopGap;
    const calendarHeadingSpace = 95.0;
    final availableRows =
        screen.height -
        spaceAboveCalendar -
        calendarHeadingSpace -
        bottomPadding;
    final rowHeight = (availableRows / weeks).clamp(44.0, 60.0);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: context.palette.isDark
            ? context.palette.panel
            : const Color(0xfff2eff4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'コーデカレンダー',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: '前の月',
                onPressed: () => onChangeMonth(-1),
                icon: const Icon(Icons.chevron_left),
                visualDensity: VisualDensity.compact,
              ),
              Text(
                '${month.year}年${month.month}月',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                tooltip: '次の月',
                onPressed: () => onChangeMonth(1),
                icon: const Icon(Icons.chevron_right),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          Row(
            children: [
              for (final day in const ['日', '月', '火', '水', '木', '金', '土'])
                Expanded(
                  child: Center(
                    child: Text(
                      day,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          for (var week = 0; week < weeks; week++)
            Row(
              children: [
                for (var day = 0; day < 7; day++)
                  Expanded(
                    child: _CalendarDay(
                      day: week * 7 + day - firstWeekday + 1,
                      daysInMonth: days,
                      month: month,
                      images: images,
                      height: rowHeight,
                      onPressed: onDayPressed,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _CalendarDay extends StatelessWidget {
  const _CalendarDay({
    required this.day,
    required this.daysInMonth,
    required this.month,
    required this.images,
    required this.height,
    required this.onPressed,
  });
  final int day;
  final int daysInMonth;
  final double height;
  final DateTime month;
  final Map<DateTime, ImageProvider> images;
  final ValueChanged<DateTime>? onPressed;

  @override
  Widget build(BuildContext context) {
    if (day > daysInMonth) return SizedBox(height: height);
    if (day < 1) {
      final previousDay = DateTime(month.year, month.month, day).day;
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            '$previousDay',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: context.palette.muted,
            ),
          ),
        ),
      );
    }
    final date = DateTime.utc(month.year, month.month, day);
    final image = images[date];
    final select = image == null ? null : onPressed;
    final cell = image == null
        ? Text(
            '$day',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          )
        : ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 38,
              height: 38,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image(
                    image: image,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const ColoredBox(color: Color(0xff555555)),
                  ),
                  const ColoredBox(color: Color(0x33000000)),
                  Center(
                    child: Text(
                      '$day',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
    return SizedBox(
      height: height,
      child: Semantics(
        container: true,
        button: select != null,
        label: image == null
            ? '${month.month}月$day日'
            : '${month.month}月$day日のコーデ',
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: select == null ? null : () => select(date),
          child: Center(child: ExcludeSemantics(child: cell)),
        ),
      ),
    );
  }
}
