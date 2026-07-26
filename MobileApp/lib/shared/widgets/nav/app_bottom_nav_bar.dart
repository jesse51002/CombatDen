import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/shared/widgets/nav/app_nav_item.dart';

enum AppBottomNavTab { home, rank, reward, videos }

String _routeFor(AppBottomNavTab tab) {
  return switch (tab) {
    AppBottomNavTab.home => AppRoutes.home,
    AppBottomNavTab.rank => AppRoutes.profile,
    AppBottomNavTab.reward => AppRoutes.pointsStore,
    AppBottomNavTab.videos => AppRoutes.videos,
  };
}

const double _kBottomNavRowHeight = 64;

/// The nav's cell grid is always FOUR columns wide, whatever the tab count.
const int _kBottomNavColumns = 4;

class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({
    super.key,
    required this.selected,
    this.tabs = AppBottomNavTab.values,
    this.onTabSelected,
  });

  final AppBottomNavTab selected;

  /// The tabs to render, in order. Defaults to the full set; every screen in
  /// the app passes the gym's filtered set (`gymNavTabs()` in `nav_tabs.dart`).
  final List<AppBottomNavTab> tabs;

  final ValueChanged<AppBottomNavTab>? onTabSelected;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: BoxDecoration(
        color: DesignConstants.backgroundColor,
        border: Border(
          top: BorderSide(
            color: DesignConstants.text3rd,
            width: DesignConstants.dividerThickness,
          ),
        ),
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: _kBottomNavRowHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // A cell is ALWAYS a quarter of the bar, and the row is centred.
            // At four tabs this is pixel-identical to an `Expanded` split; at
            // three it leaves a symmetric gutter, and at two a centred pair —
            // every tab keeps the same icon, label and tap geometry instead of
            // a 24pt icon marooned in half a phone.
            final cellWidth = constraints.maxWidth / _kBottomNavColumns;
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final tab in tabs)
                  SizedBox(
                    width: cellWidth,
                    child: AppNavItem(
                      icon: _iconFor(tab),
                      iconSlot: _iconSlotFor(tab),
                      label: _labelFor(tab),
                      isActive: tab == selected,
                      onTap: () => _handleTap(context, tab),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _handleTap(BuildContext context, AppBottomNavTab tab) {
    if (onTabSelected != null) {
      onTabSelected!(tab);
      return;
    }
    if (tab == selected) return;
    Navigator.of(context).pushReplacementNamed(_routeFor(tab));
  }

  IconData _iconFor(AppBottomNavTab tab) {
    return switch (tab) {
      AppBottomNavTab.home => Symbols.home_sharp,
      AppBottomNavTab.rank => Symbols.military_tech_sharp,
      AppBottomNavTab.reward => Symbols.card_giftcard_sharp,
      AppBottomNavTab.videos => Symbols.smart_display_sharp,
    };
  }

  String _iconSlotFor(AppBottomNavTab tab) {
    return switch (tab) {
      AppBottomNavTab.home => CombatDenSlots.navHome,
      AppBottomNavTab.rank => CombatDenSlots.navRank,
      AppBottomNavTab.reward => CombatDenSlots.navReward,
      AppBottomNavTab.videos => CombatDenSlots.navVideos,
    };
  }

  String _labelFor(AppBottomNavTab tab) {
    return switch (tab) {
      AppBottomNavTab.home => 'Home',
      // The tab is the member's whole retention surface — streak, week strip
      // and (only at a rank-enabled gym) the rank block — so it reads
      // "Profile". The enum value and the `nav_rank` icon slot keep their
      // names: they are the theme/route contract, not the label.
      AppBottomNavTab.rank => 'Profile',
      AppBottomNavTab.reward => 'Reward',
      AppBottomNavTab.videos => 'Videos',
    };
  }
}
