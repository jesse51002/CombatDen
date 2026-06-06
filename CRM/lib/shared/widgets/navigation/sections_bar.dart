import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/navigation/gym_logo.dart';
import 'package:crm/shared/widgets/navigation/nav_actions.dart';
import 'package:crm/shared/widgets/navigation/nav_sections.dart';
import 'package:crm/shared/widgets/navigation/sidebar_nav_item.dart';

/// Persistent left-side nav rail (Figma `SectionsBar`, node `5001:4340`),
/// shown at desktop widths. Below [DesignConstants.navMobileBreakpoint]
/// `AppShell` swaps this for a top bar + dropdown instead.
///
/// Items come from [kNavSections] (shared with the mobile dropdown): the gym
/// logo, then Add New Member (primary CTA, no-op for now), Dashboard, Members,
/// Growth, Schedule, Memberships, Member App, Employees, and Settings (which
/// hosts appearance + the sign-up QR codes). Each tap routes via [goToSection]
/// (`pushReplacementNamed`, so switching sections doesn't pile up route history).
///
/// Logout is pinned at the **bottom** of the rail (separated from the scrolling
/// section items): it confirms, then dispatches a sign-out the auth gate turns
/// into the return to the login screen.
class SectionsBar extends StatelessWidget {
  final String? activeRoute;

  const SectionsBar({super.key, this.activeRoute});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: DesignConstants.sideNavWidth,
      color: DesignConstants.card,
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingMedium,
        vertical: DesignConstants.spacingBig,
      ),
      // Section items scroll; Logout stays pinned to the bottom of the rail.
      // The outer Column's `spacing` provides the gap above Logout (no SizedBox
      // — gaps belong to the parent's `spacing:` per the app's spacing rules).
      child: Column(
        spacing: DesignConstants.spacingLarge,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                spacing: DesignConstants.spacingLarge,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(
                      bottom: DesignConstants.spacingMedium,
                    ),
                    child: GymLogo(size: DesignConstants.navRailLogoSize),
                  ),
                  for (final section in kNavSections)
                    SidebarNavItem(
                      icon: section.icon,
                      label: section.railText,
                      isPrimary: section.isPrimary,
                      isActive: section.route != null &&
                          activeRoute == section.route,
                      onTap: () => onNavSectionTap(context, section),
                    ),
                ],
              ),
            ),
          ),
          SidebarNavItem(
            icon: Symbols.logout_sharp,
            label: 'Logout',
            onTap: () => confirmAndLogout(context),
          ),
        ],
      ),
    );
  }
}
