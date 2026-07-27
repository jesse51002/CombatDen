import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/core/app_routes.dart';
import 'package:mobile_app/core/formats/layout_formats.dart';
import 'package:mobile_app/core/formats/theme_layout.dart';
import 'package:mobile_app/shared/widgets/nav/app_nav_item.dart';
import 'package:mobile_app/shared/widgets/nav/layouts/nav_floating_pill.dart';
import 'package:mobile_app/shared/widgets/nav/layouts/nav_four_up.dart';

enum AppBottomNavTab { home, rank, reward, videos }

String _routeFor(AppBottomNavTab tab) {
  return switch (tab) {
    AppBottomNavTab.home => AppRoutes.home,
    AppBottomNavTab.rank => AppRoutes.profile,
    AppBottomNavTab.reward => AppRoutes.pointsStore,
    AppBottomNavTab.videos => AppRoutes.videos,
  };
}

/// The persistent bottom navigation.
///
/// Tab order is fixed across every shell layout — it is muscle memory,
/// not composition — and all four destinations are always present. The
/// tenant's `app_shell_format` chooses only how the bar is drawn.
class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({
    super.key,
    required this.selected,
    this.onTabSelected,
    this.formatOverride,
  });

  final AppBottomNavTab selected;
  final ValueChanged<AppBottomNavTab>? onTabSelected;

  /// Forces a layout instead of resolving it from the customization.
  /// Used by the layout-invariant tests and the format preview.
  final AppShellFormat? formatOverride;

  @override
  Widget build(BuildContext context) {
    final format = formatOverride ?? ThemeLayout.shell();
    final pill = format == AppShellFormat.markOnly;

    final items = [
      for (final tab in AppBottomNavTab.values)
        AppNavItem(
          icon: _iconFor(tab),
          iconSlot: _iconSlotFor(tab),
          label: _labelFor(tab),
          isActive: tab == selected,
          showLabel: !pill,
          onTap: () => _handleTap(context, tab),
        ),
    ];

    return pill ? NavFloatingPill(items: items) : NavFourUp(items: items);
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
