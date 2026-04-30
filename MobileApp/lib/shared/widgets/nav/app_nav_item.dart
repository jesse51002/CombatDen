import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/design_constants.dart';

/// A single icon-over-label navigation target. Used in both top-level
/// navigation (the bottom nav bar) and any side/inline nav grid. Mirrors
/// the FlutterCRM `sidebar_nav_item.dart` pattern.
class AppNavItem extends StatelessWidget {
  const AppNavItem({
    super.key,
    required this.icon,
    required this.label,
    this.isActive = false,
    this.onTap,
    this.isPrimary = false,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback? onTap;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    Color textColor = isActive
        ? DesignConstants.text
        : DesignConstants.text2nd;
    if (isPrimary) {
      textColor = DesignConstants.primaryColor;
    }

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: DesignConstants.spacingMedium),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingTiny,
            children: [
              Icon(
                icon,
                color: textColor,
                size: 24,
                weight: DesignConstants.iconWeight,
              ),
              Text(
                label,
                style: DesignConstants.h3.copyWith(color: textColor),
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
