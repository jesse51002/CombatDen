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

class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({
    super.key,
    required this.selected,
    this.onTabSelected,
  });

  final AppBottomNavTab selected;
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
        child: Row(
          children: AppBottomNavTab.values
              .map(
                (tab) => Expanded(
                  child: AppNavItem(
                    icon: _iconFor(tab),
                    iconSlot: _iconSlotFor(tab),
                    label: _labelFor(tab),
                    isActive: tab == selected,
                    onTap: () => _handleTap(context, tab),
                  ),
                ),
              )
              .toList(growable: false),
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
      AppBottomNavTab.rank => 'Rank',
      AppBottomNavTab.reward => 'Reward',
      AppBottomNavTab.videos => 'Videos',
    };
  }
}
