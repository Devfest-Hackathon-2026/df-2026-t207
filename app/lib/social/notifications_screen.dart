import 'package:flutter/material.dart';

import '../app/app_banner.dart';
import '../app/app_loading.dart';
import '../app/app_palette.dart';
import '../capture/outfit_submission.dart';
import 'social_activity.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({
    super.key,
    required this.activity,
    required this.onOpenFriends,
    this.submission,
    this.onOpenOutfit,
    this.onOpenNotice,
    this.onDiscardOutfit,
  });

  final SocialActivity activity;
  final VoidCallback onOpenFriends;
  final OutfitSubmission? submission;
  final VoidCallback? onOpenOutfit;
  final ValueChanged<SocialNotice>? onOpenNotice;
  final VoidCallback? onDiscardOutfit;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([activity, submission]),
    builder: (context, _) {
      final notices = activity.notices;
      final job = submission;
      final hasJob =
          job?.jobId != null &&
          !notices.any(
            (notice) => notice.jobId == job!.jobId && job.result != null,
          );
      final colors = context.palette;
      return Scaffold(
        backgroundColor: colors.canvas,
        appBar: AppBar(
          backgroundColor: colors.canvas,
          surfaceTintColor: Colors.transparent,
          leading: BackButton(onPressed: () => Navigator.pop(context)),
          // 日本語の見出しは ← より 1.5dp ほど下に見えるので、少し持ち上げて揃える
          title: Transform.translate(
            offset: const Offset(0, -1.5),
            child: const Text(
              '通知',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          actionsPadding: const EdgeInsetsDirectional.only(end: 12),
          actions: [
            if (activity.hasUnread)
              TextButton.icon(
                onPressed: () => _run(context, activity.markAllRead),
                icon: const Icon(Icons.done_all),
                label: const Text('すべて既読'),
                style: TextButton.styleFrom(
                  backgroundColor: colors.control,
                  foregroundColor: colors.ink,
                  iconSize: 16,
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: AppRefreshIndicator(
            onRefresh: () => _run(context, activity.refreshNotices),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              itemCount:
                  (notices.isEmpty && !hasJob && !activity.noticesUnavailable
                      ? 1
                      : notices.length + (hasJob ? 1 : 0)) +
                  (activity.noticesUnavailable ? 1 : 0),
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                if (activity.noticesUnavailable) {
                  if (index == 0) {
                    return TextButton(
                      onPressed: () => _run(context, activity.refreshNotices),
                      child: const Text('通知を再取得'),
                    );
                  }
                  index--;
                }
                if (notices.isEmpty && !hasJob) {
                  return Padding(
                    padding: const EdgeInsets.all(28),
                    child: Center(
                      child: Text(
                        '通知はありません',
                        style: TextStyle(color: colors.muted),
                      ),
                    ),
                  );
                }
                if (hasJob && index == 0) return _jobTile(colors, job!);
                final notice = notices[index - (hasJob ? 1 : 0)];
                final unread = activity.isUnread(notice);
                return Material(
                  color: unread ? colors.control : colors.panel,
                  borderRadius: BorderRadius.circular(18),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    leading: CircleAvatar(
                      backgroundColor: colors.canvas,
                      foregroundColor: colors.ink,
                      child: Icon(switch (notice.type) {
                        'friend_request' => Icons.person_add_outlined,
                        'like' => Icons.favorite_border,
                        'outfit_ready' => Icons.checkroom_outlined,
                        _ => Icons.people_outline,
                      }, size: 21),
                    ),
                    title: Text(
                      notice.title,
                      style: TextStyle(
                        fontWeight: unread ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                    trailing:
                        notice.jobId != null &&
                            notice.jobId == job?.jobId &&
                            job?.result != null
                        ? IconButton(
                            tooltip: '処理結果を破棄',
                            onPressed: onDiscardOutfit,
                            icon: const Icon(Icons.close),
                          )
                        : unread
                        ? Semantics(
                            label: '未読',
                            child: const Icon(Icons.circle, size: 8),
                          )
                        : null,
                    onTap: () => _run(context, () async {
                      await activity.markRead(notice);
                      if (!context.mounted) return;
                      if (onOpenNotice case final open?) {
                        open(notice);
                      } else {
                        onOpenFriends();
                      }
                    }),
                  ),
                );
              },
            ),
          ),
        ),
      );
    },
  );

  Widget _jobTile(AppPalette colors, OutfitSubmission job) {
    final error = job.error;
    return Material(
      color: colors.panel,
      borderRadius: BorderRadius.circular(18),
      child: ListTile(
        leading: Icon(
          error != null ? Icons.error_outline : Icons.checkroom_outlined,
        ),
        title: Text(
          job.processing
              ? 'コーデを処理中'
              : error == null
              ? 'コーデの処理が完了しました'
              : 'コーデを処理できませんでした',
        ),
        subtitle: job.processing ? null : Text(error ?? 'タップして結果を確認'),
        onTap: job.processing ? null : onOpenOutfit,
        trailing: job.processing
            ? const AppLoadingIndicator()
            : job.result == null
            ? null
            : IconButton(
                tooltip: '処理結果を破棄',
                onPressed: onDiscardOutfit,
                icon: const Icon(Icons.close),
              ),
      ),
    );
  }

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (_) {
      if (context.mounted) {
        showAppBanner(context, '通知を更新できませんでした', icon: Icons.error_outline);
      }
    }
  }
}
