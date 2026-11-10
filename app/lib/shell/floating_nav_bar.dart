import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 下のメニューのタブ。並びは青山さんの画面のイメージ (docs/mockups) と同じ。
enum AppTab { home, search, post, community, myPage }

/// 画面の下に浮かぶ黒いメニュー。
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({
    super.key,
    required this.current,
    required this.onSelected,
  });

  final AppTab current;
  final ValueChanged<AppTab> onSelected;

  static const _items = [
    (AppTab.home, Icons.home_outlined, Icons.home, 'ホーム'),
    (AppTab.search, Icons.search, Icons.search, '探す'),
    (AppTab.post, Icons.add, Icons.add, '投稿'),
    (AppTab.community, Icons.people_outline, Icons.people, 'フレンド'),
    (AppTab.myPage, Icons.person_outline, Icons.person, 'マイページ'),
  ];

  @override
  Widget build(BuildContext context) {
    const barHeight = 64.0;
    final selectedIndex = _items.indexWhere((item) => item.$1 == current);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Material(
          color: const Color(0xff232321),
          shape: const StadiumBorder(),
          elevation: 6,
          shadowColor: const Color(0x55000000),
          child: SizedBox(
            height: barHeight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final slotWidth = constraints.maxWidth / _items.length;
                final highlightSize = math.min(48.0, slotWidth);
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedPositionedDirectional(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      start:
                          slotWidth * selectedIndex +
                          (slotWidth - highlightSize) / 2,
                      top: (barHeight - highlightSize) / 2,
                      width: highlightSize,
                      height: highlightSize,
                      child: const IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color(0x33ffffff),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (final (tab, icon, selectedIcon, label) in _items)
                          Expanded(
                            child: Center(
                              child: _NavButton(
                                icon: tab == current ? selectedIcon : icon,
                                label: label,
                                selected: tab == current,
                                onPressed: () => onSelected(tab),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      child: IconButton(
        onPressed: onPressed,
        tooltip: label,
        iconSize: 26,
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          backgroundColor: Colors.transparent,
        ),
        icon: Icon(
          icon,
          color: selected ? Colors.white : const Color(0xffbdbdb8),
        ),
      ),
    );
  }
}
