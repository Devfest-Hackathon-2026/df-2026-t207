import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../app/app_page_transitions.dart';
import '../capture/outfit_camera_screen.dart';
import 'coming_soon_page.dart';
import 'floating_nav_bar.dart';

/// タブの中身を作る関数。`goTo` で別のタブへ移れる (例: ホームから近くのコーデへ)。
typedef ShellPageBuilder = Widget Function(
  BuildContext context,
  ValueChanged<AppTab> goTo,
);

/// ログインの後の土台。下のメニューでホーム・探す・フレンド・マイページを切り替え、
/// 「投稿」はタブにせずカメラを開く。
///
/// タブの画面は切り替えても作り直さない (スクロールの位置などを保つ)。
/// まだ無いタブは「準備中」の画面を出す。
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.homeBuilder,
    required this.myPageBuilder,
    this.searchBuilder,
    this.communityBuilder,
    this.onSearchPressed,
    this.onPostPressed,
    this.onPhotoConfirmed,
    this.initialTab = AppTab.home,
  }) : assert(initialTab != AppTab.post);

  final ShellPageBuilder homeBuilder;
  final ShellPageBuilder myPageBuilder;

  /// 探す (近くのコーデ、仕様書の S4)。無ければ準備中。
  final ShellPageBuilder? searchBuilder;

  /// 全画面で近くのコーデを開く時に使う。
  final void Function(BuildContext context)? onSearchPressed;

  /// フレンド (S15)。無ければ準備中。
  final ShellPageBuilder? communityBuilder;

  /// 投稿を押した時。省略するとカメラと写真確認画面を開く。
  final void Function(BuildContext context)? onPostPressed;
  final Future<void> Function(XFile photo)? onPhotoConfirmed;

  final AppTab initialTab;

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell>
    with SingleTickerProviderStateMixin {
  static const _tabs = [
    AppTab.home,
    AppTab.search,
    AppTab.community,
    AppTab.myPage,
  ];

  late AppTab _current = widget.initialTab;
  late final _tabTransition = AnimationController(
    vsync: this,
    duration: AppPageTransitionsBuilder.duration,
    value: 1,
  );
  final _communityNavigatorKey = GlobalKey<NavigatorState>();
  final _communityObserver = _CommunityNavigatorObserver();
  ModalRoute<dynamic>? _returningCommunityProfile;

  void selectTab(AppTab tab) => _goTo(tab);

  void openCommunityPage(Route<void> page) {
    final navigator = _communityNavigatorKey.currentState;
    if (navigator == null) return;
    _goTo(AppTab.community);
    navigator.push<void>(page);
  }

  bool _closeCommunityProfile({required bool animated}) {
    if (!animated) {
      // 一覧へ戻る途中で別タブに移った場合も、再表示時にはプロフィールを出さない。
      _returningCommunityProfile?.offstage = true;
    }
    final navigator = _communityNavigatorKey.currentState;
    final route = _communityObserver.topRoute;
    if (navigator == null || route == null || route.isFirst) return false;
    if (animated && route is ModalRoute<dynamic>) {
      _returningCommunityProfile = route;
      route.completed.then((_) {
        if (identical(_returningCommunityProfile, route)) {
          _returningCommunityProfile = null;
        }
      });
      navigator.pop();
    } else {
      navigator.removeRoute(route);
    }
    return true;
  }

  void _goTo(AppTab tab) {
    if (tab == AppTab.search && widget.onSearchPressed != null) {
      widget.onSearchPressed!(context);
      return;
    }
    if (tab == AppTab.post) {
      _openPost();
      return;
    }
    if (_current == AppTab.community) {
      _closeCommunityProfile(animated: tab == AppTab.community);
    }
    if (tab == _current) return;
    setState(() => _current = tab);
    if (!MediaQuery.disableAnimationsOf(context)) {
      _tabTransition.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _tabTransition.dispose();
    super.dispose();
  }

  Future<void> _openPost() async {
    if (widget.onPostPressed != null) {
      widget.onPostPressed!(context);
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            OutfitCameraScreen(onPhotoConfirmed: widget.onPhotoConfirmed),
      ),
    );
  }

  Widget _page(AppTab tab) {
    switch (tab) {
      case AppTab.home:
        return widget.homeBuilder(context, _goTo);
      case AppTab.myPage:
        return widget.myPageBuilder(context, _goTo);
      case AppTab.search:
        return widget.searchBuilder?.call(context, _goTo) ??
            const ComingSoonPage(
              title: '探す',
              message: 'すれ違った人の今日のコーデが、ここに並びます。',
              icon: Icons.people_outline,
            );
      case AppTab.community:
        final builder = widget.communityBuilder;
        if (builder == null) {
          return const ComingSoonPage(
            title: 'フレンド',
            message: 'フレンドの一覧は、あとで追加します。',
            icon: Icons.groups_outlined,
          );
        }
        return HeroControllerScope.none(
          child: Navigator(
            key: _communityNavigatorKey,
            observers: [_communityObserver],
            pages: [
              MaterialPage<void>(
                key: const ValueKey(AppTab.community),
                child: builder(context, _goTo),
              ),
            ],
            onDidRemovePage: (_) {},
          ),
        );
      case AppTab.post:
        throw StateError('投稿はタブにしない');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Android の戻るは、フレンドの詳細から一覧へ、他のタブからホームへ戻す。
      canPop: _current == AppTab.home,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_current == AppTab.community &&
            _closeCommunityProfile(animated: true)) {
          return;
        }
        _goTo(AppTab.home);
      },
      child: Scaffold(
        extendBody: true,
        body: centerFadeTransition(
          context,
          _tabTransition,
          IndexedStack(
            index: _tabs.indexOf(_current),
            children: [for (final tab in _tabs) _page(tab)],
          ),
          initialOpacity: 0.65,
        ),
        bottomNavigationBar: FloatingNavBar(
          current: _current,
          onSelected: _goTo,
        ),
      ),
    );
  }
}

class _CommunityNavigatorObserver extends NavigatorObserver {
  Route<dynamic>? topRoute;

  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    this.topRoute = topRoute;
  }
}
