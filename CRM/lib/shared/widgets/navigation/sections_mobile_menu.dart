import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/shared/widgets/navigation/nav_sections.dart';

/// The mobile nav dropdown — a frosted, full-width panel that drops below the
/// [AppTopBar]. The mobile counterpart of the desktop [SectionsBar]: the same
/// [kNavSections] rendered as full-width rows (icon + label, active row in
/// sapphire), then a pinned Logout row. Mirrors the theme browser's
/// `ThemeBrowserMobileMenu` so the two surfaces read the same.
///
/// The top bar owns open/close; every callback here is already wired to
/// close-then-act.
class SectionsMobileMenu extends StatelessWidget {
  const SectionsMobileMenu({
    super.key,
    required this.activeRoute,
    required this.onSelect,
    required this.onLogout,
  });

  final String? activeRoute;

  /// Tapped a section row — the top bar closes the menu, then routes.
  final void Function(NavSection section) onSelect;

  /// Tapped Logout — the top bar closes the menu, then confirms + signs out.
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: DesignConstants.backgroundColor.withValues(alpha: 0.92),
            border: Border(
              bottom: BorderSide(color: DesignConstants.line),
            ),
            boxShadow: DesignConstants.cardShadow,
          ),
          // The menu lives in the app Overlay, which has no Material ancestor,
          // so the rows' InkWells need their own. Transparent type keeps the
          // frosted background visible and adds ink/splash on tap.
          child: Material(
            type: MaterialType.transparency,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                DesignConstants.paddingSmall,
                DesignConstants.spacingMedium,
                DesignConstants.paddingSmall,
                DesignConstants.spacingLarge,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                spacing: DesignConstants.spacingSmall,
                children: [
                  for (final section in visibleNavSections(selectedGym.role))
                    _MobileNavRow(
                      icon: section.icon,
                      label: section.label,
                      isActive: section.route != null &&
                          activeRoute == section.route,
                      isPrimary: section.isPrimary,
                      onTap: () => onSelect(section),
                    ),
                  _MobileNavRow(
                    icon: Symbols.logout_sharp,
                    label: 'Logout',
                    onTap: onLogout,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One full-width row in the mobile dropdown: icon + label with a soft bottom
/// separator. Active rows (and the primary CTA) paint sapphire, matching the
/// rail's [SidebarNavItem] colors.
class _MobileNavRow extends StatelessWidget {
  const _MobileNavRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
    this.isPrimary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final Color color = isActive || isPrimary
        ? DesignConstants.primaryColor
        : DesignConstants.text;

    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: DesignConstants.lineSoft),
          ),
        ),
        padding: const EdgeInsets.symmetric(
          vertical: DesignConstants.spacingMedium,
        ),
        child: Row(
          spacing: DesignConstants.spacingMedium,
          children: [
            Icon(
              icon,
              color: color,
              size: DesignConstants.iconSizeLarge,
              weight: DesignConstants.iconWeight,
            ),
            Text(label, style: DesignConstants.navLinkMobile.copyWith(
              color: color,
            )),
          ],
        ),
      ),
    );
  }
}
