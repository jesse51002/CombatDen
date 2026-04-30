import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mobile_app/core/constants/design_constants.dart';
import 'package:mobile_app/shared/widgets/nav/app_nav_item.dart';

enum AppBottomNavTab { home, rank, reward, videos }

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
            width: DesignConstants.buttonBorder,
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
                    label: _labelFor(tab),
                    isActive: tab == selected,
                    onTap: onTabSelected == null
                        ? null
                        : () => onTabSelected!(tab),
                  ),
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }

  IconData _iconFor(AppBottomNavTab tab) {
    return switch (tab) {
      AppBottomNavTab.home => Symbols.home_sharp,
      AppBottomNavTab.rank => Symbols.military_tech_sharp,
      AppBottomNavTab.reward => Symbols.card_giftcard_sharp,
      AppBottomNavTab.videos => Symbols.smart_display_sharp,
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
