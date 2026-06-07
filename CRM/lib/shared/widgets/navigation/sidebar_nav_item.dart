import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// A single navigation item in the left sidebar (icon + 1-2 line label).
///
/// The active item is marked two ways: its icon+label paint in `primaryColor`
/// (sapphire) and a sapphire accent bar runs down its left edge. `isPrimary`
/// also paints the item in `primaryColor` but carries no bar — that absent bar
/// is what tells the always-sapphire "Add New Member" CTA apart from whichever
/// section is currently active.
class SidebarNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final bool isPrimary;
  final VoidCallback? onTap;

  const SidebarNavItem({
    super.key,
    required this.icon,
    required this.label,
    this.isActive = false,
    this.isPrimary = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color color = isActive || isPrimary
        ? DesignConstants.primaryColor
        : DesignConstants.text2nd;

    return InkWell(
      onTap: onTap,
      // Stack so the active accent bar overlays the left edge without shifting
      // the centered icon/label — the content sits identically whether or not
      // the item is active; only the bar appears.
      child: Stack(
        children: [
          if (isActive)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(
                width: DesignConstants.navActiveIndicatorWidth,
                decoration: BoxDecoration(
                  color: DesignConstants.primaryColor,
                  borderRadius: BorderRadius.circular(
                    DesignConstants.radiusSmall,
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: DesignConstants.spacingMedium,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: DesignConstants.spacingTiny,
                children: [
                  Icon(
                    icon,
                    color: color,
                    size: DesignConstants.iconSizeLarge,
                    weight: DesignConstants.iconWeight,
                  ),
                  Text(
                    label,
                    style: DesignConstants.h3.copyWith(color: color),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
