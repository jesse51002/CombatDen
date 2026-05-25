import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/core/navigation/app_routes.dart';
import 'package:app_management/shared/widgets/sidebar_nav_item.dart';

/// Persistent left-side nav rail (Figma `SectionsBar`, node `5001:4340`).
///
/// Items, top to bottom: COMBAT DEN logo, Add New Member (primary CTA,
/// no-op for now — Add Member flow is out of scope this pass), Dashboard,
/// Members, Growth, Schedule, Member App, Employees (no-op), Sign up
/// QR Codes, Settings (no-op). Each tap calls `pushReplacementNamed`
/// so we don't pile up route history when switching sections.
class SectionsBar extends StatelessWidget {
  final String? activeRoute;

  const SectionsBar({super.key, this.activeRoute});

  void _go(BuildContext context, String route) {
    if (route == activeRoute) return;
    Navigator.of(context).pushReplacementNamed(route);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      color: DesignConstants.card,
      padding: const EdgeInsets.symmetric(
        horizontal: DesignConstants.spacingMedium,
        vertical: DesignConstants.spacingBig,
      ),
      child: SingleChildScrollView(
        child: Column(
          spacing: DesignConstants.spacingLarge,
          children: [
            const _Logo(),
            SidebarNavItem(
              icon: Symbols.person_add_sharp,
              label: 'Add\nNew Member',
              isPrimary: true,
              onTap: () =>
                  debugPrint('Add Member flow is out of scope this pass'),
            ),
            SidebarNavItem(
              icon: Symbols.tv_sharp,
              label: 'Dashboard',
              isActive: activeRoute == AppRoutes.home,
              onTap: () => _go(context, AppRoutes.home),
            ),
            SidebarNavItem(
              icon: Symbols.group_sharp,
              label: 'Members',
              isActive: activeRoute == AppRoutes.members,
              onTap: () => _go(context, AppRoutes.members),
            ),
            SidebarNavItem(
              icon: Symbols.trending_up_sharp,
              label: 'Growth',
              isActive: activeRoute == AppRoutes.growth,
              onTap: () => _go(context, AppRoutes.growth),
            ),
            SidebarNavItem(
              icon: Symbols.calendar_today_sharp,
              label: 'Schedule',
              isActive: activeRoute == AppRoutes.schedule,
              onTap: () => _go(context, AppRoutes.schedule),
            ),
            SidebarNavItem(
              icon: Symbols.bolt_sharp,
              label: 'Member\nApp',
              isActive: activeRoute == AppRoutes.memberAppPreview,
              onTap: () => _go(context, AppRoutes.memberAppPreview),
            ),
            SidebarNavItem(
              icon: Symbols.watch_sharp,
              label: 'Employees',
              onTap: () =>
                  debugPrint('Employees screen is out of scope this pass'),
            ),
            SidebarNavItem(
              icon: Symbols.qr_code_sharp,
              label: 'Sign up\nQR Codes',
              isActive: activeRoute == AppRoutes.qrCodes,
              onTap: () => _go(context, AppRoutes.qrCodes),
            ),
            SidebarNavItem(
              icon: Symbols.settings_sharp,
              label: 'Settings',
              onTap: () =>
                  debugPrint('Settings screen is out of scope this pass'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Apex MMA logo. An image asset, so swapping in a real gym logo is a
/// one-line change (drop the file in assets/images/ and update the path).
class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignConstants.spacingMedium),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
        child: Image.asset(
          'assets/images/apexmma-logo-simple.png',
          width: 64,
          height: 64,
        ),
      ),
    );
  }
}
