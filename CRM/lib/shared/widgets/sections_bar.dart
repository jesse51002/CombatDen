import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:theme_flutter/customization_runtime.dart';
import 'package:crm/showcase/showcase_slots.dart';
import 'package:theme_flutter/theme/theme_image.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/login/bloc/login_bloc.dart';
import 'package:crm/features/login/bloc/login_event.dart';
import 'package:crm/shared/widgets/confirmation_modal.dart';
import 'package:crm/shared/widgets/sidebar_nav_item.dart';

/// Persistent left-side nav rail (Figma `SectionsBar`, node `5001:4340`).
///
/// Items, top to bottom: the managed gym's logo, Add New Member (primary CTA,
/// no-op for now — Add Member flow is out of scope this pass), Dashboard,
/// Members, Growth, Schedule, Member App, Employees, Sign up
/// QR Codes, Settings (no-op). Each tap calls `pushReplacementNamed`
/// so we don't pile up route history when switching sections.
///
/// Logout is pinned at the **bottom** of the rail (separated from the scrolling
/// section items): it confirms, then dispatches [LoginSignOutRequested], which
/// the auth gate turns into the return to the login screen.
class SectionsBar extends StatelessWidget {
  final String? activeRoute;

  const SectionsBar({super.key, this.activeRoute});

  /// Confirm, then sign out. Reads the [LoginBloc] *before* the await so the
  /// dispatch never touches a `BuildContext` across the async gap. The auth
  /// gate (a `BlocBuilder` on [LoginBloc]) swaps back to the login screen on
  /// the resulting `LoginUnauthenticated`, and tearing this subtree down clears
  /// [selectedGym] — so no navigation is needed here.
  Future<void> _logout(BuildContext context) async {
    final bloc = context.read<LoginBloc>();
    final confirmed = await ConfirmationModal.show(
      context: context,
      title: 'Log out?',
      message: 'You’ll need to sign in again to manage your gym.',
      confirmLabel: 'Log out',
    );
    if (!confirmed) return;
    bloc.add(const LoginSignOutRequested());
  }

  void _go(BuildContext context, String route) {
    // Skip only when we're truly already on that screen. Compare to the
    // *actual* current route, not [activeRoute] — a detail sub-screen
    // (e.g. member detail) highlights its parent section via [activeRoute]
    // while living on its own route, so tapping that section must still
    // navigate back to the section root instead of no-opping.
    final currentRoute = ModalRoute.of(context)?.settings.name;
    if (route == currentRoute) return;
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
                  const _Logo(),
                  SidebarNavItem(
                    icon: Symbols.person_add_sharp,
                    label: 'Add\nNew Member',
                    isPrimary: true,
                    onTap: () => debugPrint(
                      'Add Member flow is out of scope this pass',
                    ),
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
                    icon: Symbols.badge_sharp,
                    label: 'Employees',
                    isActive: activeRoute == AppRoutes.employees,
                    onTap: () => _go(context, AppRoutes.employees),
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
                    onTap: () => debugPrint(
                      'Settings screen is out of scope this pass',
                    ),
                  ),
                ],
              ),
            ),
          ),
          SidebarNavItem(
            icon: Symbols.logout_sharp,
            label: 'Logout',
            onTap: () => _logout(context),
          ),
        ],
      ),
    );
  }
}

/// The managed gym's logo. Resolves the **selected style's** `logo_primary`
/// slot — the same brand logo the member app shows — so the rail reflects the
/// gym the admin is managing instead of a fixed brand. Falls back to the
/// bundled default until a gym is selected.
///
/// Rebrands on two signals: [selectedGym] (the pick) and, once the theme
/// engine is up, [ThemeRuntime.changes] (the new design's config finishing
/// loading). The second matters because the config load lands *after* the
/// pick notifies — listening to the pick alone leaves the logo one selection
/// behind until the engine catches up.
class _Logo extends StatefulWidget {
  const _Logo();

  @override
  State<_Logo> createState() => _LogoState();
}

class _LogoState extends State<_Logo> {
  // The engine's change-listenable, held once attached so dispose can detach
  // without re-resolving it (it throws until the engine is registered).
  Listenable? _themeChanges;

  @override
  void initState() {
    super.initState();
    selectedGym.addListener(_onChanged);
    _attachThemeListener();
  }

  @override
  void dispose() {
    selectedGym.removeListener(_onChanged);
    _themeChanges?.removeListener(_onChanged);
    super.dispose();
  }

  // The theme engine initializes lazily (first time the Theme tab mounts), so
  // its listenable isn't there at app start. Attach as soon as it's ready —
  // re-tried on every [selectedGym] notify, since a pick guarantees the engine
  // is up by then.
  void _attachThemeListener() {
    if (_themeChanges != null || !ThemeRuntime.isReady) return;
    _themeChanges = ThemeRuntime.changes..addListener(_onChanged);
  }

  void _onChanged() {
    _attachThemeListener();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignConstants.spacingMedium),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
        child: Image(
          image: ThemeImage.image(
            ShowcaseSlots.logoPrimary,
            fallback: const AssetImage(
              'assets/images/apexmma-logo-simple.png',
            ),
          ),
          width: 64,
          height: 64,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
