import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';

/// The pill row across the top of the videos screen (All / Education /
/// Entertainment). Selecting a pill re-filters the feed in place via
/// [onTabSelected].
class VideoCategoryTabs extends StatelessWidget {
  const VideoCategoryTabs({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    this.onTabSelected,
  });

  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int>? onTabSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: DesignConstants.screenHorizontalPadding,
        vertical: DesignConstants.spacingLarge,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: DesignConstants.spacingLarge,
        children: [
          for (var i = 0; i < tabs.length; i++)
            _CategoryPill(
              label: tabs[i],
              isActive: i == selectedIndex,
              onTap: () => onTabSelected?.call(i),
            ),
        ],
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = isActive
        ? DesignConstants.primaryColor
        : DesignConstants.backgroundColor;
    final fg = isActive ? DesignConstants.text : DesignConstants.text2nd;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: DesignConstants.paddingSmall,
          vertical: DesignConstants.spacingMedium,
        ),
        child: Text(label, style: DesignConstants.h3.copyWith(color: fg)),
      ),
    );
  }
}
