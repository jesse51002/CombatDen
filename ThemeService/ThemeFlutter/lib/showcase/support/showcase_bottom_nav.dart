import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:theme_flutter/showcase/showcase_slots.dart';
import 'package:theme_flutter/showcase/showcase_tokens.dart';
import 'package:theme_flutter/theme/theme_icon.dart';

/// Clone of MobileApp's `AppBottomNavBar` + `AppNavItem`. Preview-only:
/// taps are no-ops (no routing). Icons are brand-overridable via ThemeIcon.
enum ShowcaseNavTab { home, rank, reward, videos }

const double _kBottomNavRowHeight = 64;

class ShowcaseBottomNav extends StatelessWidget {
  const ShowcaseBottomNav({super.key, required this.selected});

  final ShowcaseNavTab selected;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: BoxDecoration(
        color: ShowcaseTokens.backgroundColor,
        border: Border(
          top: BorderSide(
            color: ShowcaseTokens.text3rd,
            width: ShowcaseTokens.dividerThickness,
          ),
        ),
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: _kBottomNavRowHeight,
        child: Row(
          children: ShowcaseNavTab.values
              .map(
                (tab) => Expanded(
                  child: _NavItem(
                    icon: _iconFor(tab),
                    iconSlot: _slotFor(tab),
                    label: _labelFor(tab),
                    isActive: tab == selected,
                  ),
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }

  IconData _iconFor(ShowcaseNavTab tab) => switch (tab) {
    ShowcaseNavTab.home => Symbols.home_sharp,
    ShowcaseNavTab.rank => Symbols.military_tech_sharp,
    ShowcaseNavTab.reward => Symbols.card_giftcard_sharp,
    ShowcaseNavTab.videos => Symbols.smart_display_sharp,
  };

  String _slotFor(ShowcaseNavTab tab) => switch (tab) {
    ShowcaseNavTab.home => ShowcaseSlots.navHome,
    ShowcaseNavTab.rank => ShowcaseSlots.navRank,
    ShowcaseNavTab.reward => ShowcaseSlots.navReward,
    ShowcaseNavTab.videos => ShowcaseSlots.navVideos,
  };

  String _labelFor(ShowcaseNavTab tab) => switch (tab) {
    ShowcaseNavTab.home => 'Home',
    ShowcaseNavTab.rank => 'Rank',
    ShowcaseNavTab.reward => 'Reward',
    ShowcaseNavTab.videos => 'Videos',
  };
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.iconSlot,
    required this.label,
    required this.isActive,
  });

  final IconData icon;
  final String iconSlot;
  final String label;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? ShowcaseTokens.accent : ShowcaseTokens.text2nd;
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: ShowcaseTokens.spacingMedium,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: ShowcaseTokens.spacingTiny,
          children: [
            ThemeIcon.widget(
              context,
              slot: iconSlot,
              fallback: icon,
              color: color,
              size: ShowcaseTokens.iconSizeMd,
            ),
            Text(
              label,
              style: ShowcaseTokens.h3.copyWith(color: color),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
