import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';

/// A single navigation item in the left sidebar (icon + 1-2 line label).
///
/// Adapted from `../FlutterCRM/lib/shared/widgets/sidebar_nav_item.dart`.
/// `isPrimary` paints the item in `primaryColor` regardless of `isActive`
/// — used for the "Add New Member" CTA.
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
    Color color = isActive
        ? DesignConstants.text
        : DesignConstants.text2nd;
    if (isPrimary) {
      color = DesignConstants.primaryColor;
    }

    return InkWell(
      onTap: onTap,
      child: Padding(
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
                size: 24,
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
    );
  }
}
