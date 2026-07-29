import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:theme_flutter/theme/theme_icon.dart';

/// A single icon-over-label navigation target. Used in top-level
/// navigation (the bottom nav bar).
///
/// The icon is ThemeService-overridable via `ThemeIcon.widget`: it
/// draws the tenant SVG for [iconSlot] when present and falls back to [icon]
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
    this.showLabel = true,
  });

  /// `Symbols.*_sharp` fallback drawn when [iconSlot] has no override.
  final IconData icon;

  /// ThemeConfig slot id for the brandable icon (see `CombatDenSlots`).
  final String iconSlot;
  final String label;
  final bool isActive;
  final VoidCallback? onTap;
  final bool isPrimary;

  /// When false the label is not laid out, but it is still built and
  /// still announced, so an icon-only nav keeps its accessible name.
  final bool showLabel;

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
              ThemeIcon.widget(
                context,
                slot: iconSlot,
                fallback: icon,
                color: textColor,
                size: DesignConstants.iconSizeMd,
              ),
              if (showLabel)
                Text(
                  label,
                  style: DesignConstants.h3.copyWith(color: textColor),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                )
              else
                Semantics(label: label, child: const SizedBox.shrink()),
            ],
          ),
        ),
      ),
    );
  }
}
