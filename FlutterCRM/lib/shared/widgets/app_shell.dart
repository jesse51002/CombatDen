import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/sidebar_nav_item.dart';

/// The global app shell with left navigation sidebar.
///
/// Wraps authenticated screens with the left nav rail.
/// The right sidebar and main content are provided by
/// the child.
class AppShell extends StatelessWidget {
  final Widget child;
  final String? activeRoute;

  const AppShell({
    super.key,
    required this.child,
    this.activeRoute,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignConstants.backgroundColor,
      body: Row(
        children: [
          _LeftSidebar(activeRoute: activeRoute),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _LeftSidebar extends StatelessWidget {
  final String? activeRoute;

  const _LeftSidebar({this.activeRoute});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80.0,
      color: DesignConstants.backgroundColor,
      child: Column(
        children: [
          const SizedBox(
            height:
                DesignConstants.spacingLarge,
          ),
          // Logo
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal:
                  DesignConstants.spacingSmall,
            ),
            child: Text(
              'COMBAT\nDEN',
              textAlign: TextAlign.center,
              style: DesignConstants.h3.copyWith(
                color: DesignConstants.primaryColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(
            height:
                DesignConstants.spacingLarge,
          ),
          // Nav items
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  SidebarNavItem(
                    icon: Icons.person_add,
                    label: 'Add New\nMember',
                    isActive:
                        activeRoute == 'add_member',
                  ),
                  SidebarNavItem(
                    icon: Icons.calendar_today,
                    label: 'Dashboard',
                    isActive:
                        activeRoute == 'dashboard',
                  ),
                  SidebarNavItem(
                    icon: Icons.people,
                    label: 'Members',
                    isActive:
                        activeRoute == 'members',
                  ),
                  SidebarNavItem(
                    icon: Icons.trending_up,
                    label: 'Growth',
                    isActive: activeRoute == 'growth',
                  ),
                  SidebarNavItem(
                    icon: Icons.event,
                    label: 'Schedule',
                    isActive:
                        activeRoute == 'schedule',
                  ),
                  SidebarNavItem(
                    icon: Icons.loyalty,
                    label: 'Member-\nships',
                    isActive:
                        activeRoute == 'memberships',
                  ),
                  SidebarNavItem(
                    icon: Icons.bolt,
                    label: 'Member\nApp',
                    isActive:
                        activeRoute == 'member_app',
                  ),
                  SidebarNavItem(
                    icon: Icons.badge,
                    label: 'Employees',
                    isActive:
                        activeRoute == 'employees',
                  ),
                  SidebarNavItem(
                    icon: Icons.qr_code,
                    label: 'Sign up\nQR Codes',
                    isActive:
                        activeRoute == 'qr_codes',
                  ),
                  SidebarNavItem(
                    icon: Icons.settings,
                    label: 'Settings',
                    isActive:
                        activeRoute == 'settings',
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
