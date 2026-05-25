import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/customization/widgets/branded_icon.dart';

/// A single icon-over-label navigation target. Used in top-level
/// navigation (the bottom nav bar). Mirrors the FlutterCRM
/// `sidebar_nav_item.dart` pattern.
///
/// The icon is a CustomizationService-overridable `BrandedIcon`: it draws
/// the tenant SVG for [iconSlot] when present and falls back to [icon]
/// (a `Symbols.*_sharp`) otherwise.
class AppNavItem extends StatelessWidget {
  const AppNavItem({
    super.key,
    required this.icon,
    required this.iconSlot,
    required this.label,
    this.isActive = false,
    this.onTap,
    this.isPrimary = false,
  });

  /// `Symbols.*_sharp` fallback drawn when [iconSlot] has no override.
  final IconData icon;

  /// Customization slot id for the brandable icon (see `CombatDenSlots`).
  final String iconSlot;
  final String label;
  final bool isActive;
  final VoidCallback? onTap;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    Color textColor = isActive
        ? DesignConstants.accent
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
              BrandedIcon(
                slot: iconSlot,
                fallback: icon,
                color: textColor,
                size: DesignConstants.iconSizeMd,
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
