import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/app_constants.dart';
import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/login/bloc/login_bloc.dart';
import 'package:crm/features/login/bloc/login_event.dart';
import 'package:crm/features/login/bloc/login_state.dart';
import 'package:crm/features/login/presentation/screens/login_screen.dart';
import 'package:crm/shared/widgets/sidebar_nav_item.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The global app shell with left navigation sidebar.
///
/// Wraps authenticated screens with the left nav rail.
/// The right sidebar and main content are provided by
/// the child.
class AppShell extends StatelessWidget {
  final Widget child;
  final String? activeRoute;
  final Widget? rightBar;
  final double? contentPadding;

  const AppShell({
    super.key,
    required this.child,
    this.activeRoute,
    this.rightBar,
    this.contentPadding,
  });

  @override
  Widget build(BuildContext context) {
    return BlocListener<LoginBloc, LoginState>(
      listener: (context, state) {
        if (state is LoginUnauthenticated) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute<void>(
              builder: (_) => const LoginScreen(),
            ),
            (_) => false,
          );
        }
      },
      child: Scaffold(
        backgroundColor: DesignConstants.backgroundColor,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final double padding;
            if (contentPadding != null) {
              padding = contentPadding!;
            } else if (width <
                AppConstants.breakpointPhone) {
              padding = DesignConstants.spacingLarge;
            } else if (width <
                AppConstants.breakpointTablet) {
              padding = DesignConstants.spacingBig;
            } else {
              padding = 64;
            }

            return Row(
              children: [
                _LeftSidebar(activeRoute: activeRoute),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: padding,
                    ),
                    child: child,
                  ),
                ),
                ?rightBar,
              ],
            );
          },
        ),
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
      color: DesignConstants.card,
      child: Column(
        children: [
          const SizedBox(
            height:
                DesignConstants.spacingBig,
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
              style: DesignConstants.h2.copyWith(
                color: DesignConstants.text,
                fontWeight: FontWeight.w900,
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
              child: Padding(
                padding: EdgeInsetsGeometry.symmetric(
                  horizontal: DesignConstants.spacingMedium), 
                child: Column(
                  children: [
                    SidebarNavItem(
                      icon: Symbols.person_add_sharp,
                      label: 'Add New\nMember',
                      isActive:
                          activeRoute == 'add_member',
                      isPrimary: true,
                    ),
                    SidebarNavItem(
                      icon: Symbols.calendar_today_sharp,
                      label: 'Dashboard',
                      isActive:
                          activeRoute == 'dashboard',
                    ),
                    SidebarNavItem(
                      icon: Symbols.people_sharp,
                      label: 'Members',
                      isActive:
                          activeRoute == 'members',
                    ),
                    SidebarNavItem(
                      icon: Symbols.trending_up_sharp,
                      label: 'Growth',
                      isActive: activeRoute == 'growth',
                    ),
                    SidebarNavItem(
                      icon: Symbols.event_sharp,
                      label: 'Schedule',
                      isActive:
                          activeRoute == 'schedule',
                    ),
                    SidebarNavItem(
                      icon: Symbols.loyalty_sharp,
                      label: 'Memberships',
                      isActive:
                          activeRoute == 'memberships',
                    ),
                    SidebarNavItem(
                      icon: Symbols.bolt_sharp,
                      label: 'Member\nApp',
                      isActive:
                          activeRoute == 'member_app',
                    ),
                    SidebarNavItem(
                      icon: Symbols.badge_sharp,
                      label: 'Employees',
                      isActive:
                          activeRoute == 'employees',
                    ),
                    SidebarNavItem(
                      icon: Symbols.qr_code_sharp,
                      label: 'Sign up\nQR Codes',
                      isActive:
                          activeRoute == 'qr_codes',
                    ),
                    SidebarNavItem(
                      icon: Symbols.settings_sharp,
                      label: 'Settings',
                      isActive:
                          activeRoute == 'settings',
                    ),
                  ],
                )
              ),
            ),
          ),
          const SizedBox(
            height: DesignConstants.spacingMedium,
          ),
          SidebarNavItem(
            icon: Symbols.logout_sharp,
            label: 'Logout',
            onTap: () {
              context.read<LoginBloc>().add(
                    const LoginSignOutRequested(),
                  );
            },
          ),
          const SizedBox(
            height: DesignConstants.spacingLarge,
          ),
        ],
      ),
    );
  }
}
