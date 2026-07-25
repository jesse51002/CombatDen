import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/auth/employee_role.dart';
import 'package:crm/core/auth/role_policy.dart';
import 'package:crm/core/navigation/app_routes.dart';

/// A nav item that opens a flow instead of navigating to a route. Both these
/// items carry `route: null` and are dispatched by [action] (see
/// `onNavSectionTap`), not by a route push.
enum NavSectionAction {
  /// The "Add New Member" primary CTA opens the add-member flow.
  addMember,

  /// "Kiosk Mode" opens a confirm dialog, then enters kiosk (locks the iPad
  /// to the member self-serve surface).
  enterKiosk,
}

/// One entry in the app's primary navigation, shared by the desktop rail
/// ([SectionsBar]) and the mobile dropdown ([SectionsMobileMenu]) so both
/// render the exact same items in the same order — change the nav once, here.
///
/// [route] is `null` for the two flow-opening items ("Add New Member" and
/// "Kiosk Mode"), which carry an [action] instead and open a flow rather than
/// navigating. Every other item has a [route] and navigates.
class NavSection {
  final IconData icon;

  /// Flat, single-line label — used by the mobile dropdown rows.
  final String label;

  /// The rail's hand-tuned label, which may carry a deliberate `\n` line break
  /// (e.g. `'Member\nApp'`) so two-word items wrap cleanly in the narrow rail.
  /// Falls back to [label] when the rail label is identical.
  final String? railLabel;

  /// Target route, or `null` for a flow-opening item (which carries an
  /// [action] instead of navigating to a route).
  final String? route;

  /// The always-sapphire primary CTA ("Add New Member") — painted like the
  /// active item but without the active accent bar.
  final bool isPrimary;

  /// For a flow-opening item (`route == null`): which flow the tap opens.
  /// `null` for ordinary route items.
  final NavSectionAction? action;

  const NavSection({
    required this.icon,
    required this.label,
    this.railLabel,
    this.route,
    this.isPrimary = false,
    this.action,
  });

  /// Label as shown in the rail (deliberate wrap if one was given).
  String get railText => railLabel ?? label;
}

/// The ordered primary nav, top to bottom. The gym logo and Logout are chrome
/// owned by the rail/top-bar themselves, not entries here.
const List<NavSection> kNavSections = [
  NavSection(
    icon: Symbols.person_add_sharp,
    label: 'Add New Member',
    railLabel: 'Add\nNew Member',
    isPrimary: true,
    action: NavSectionAction.addMember,
  ),
  NavSection(
    icon: Symbols.tv_sharp,
    label: 'Dashboard',
    route: AppRoutes.home,
  ),
  NavSection(
    icon: Symbols.group_sharp,
    label: 'People',
    route: AppRoutes.members,
  ),
  NavSection(
    icon: Symbols.trending_up_sharp,
    label: 'Growth',
    route: AppRoutes.growth,
  ),
  NavSection(
    icon: Symbols.calendar_today_sharp,
    label: 'Schedule',
    route: AppRoutes.schedule,
  ),
  NavSection(
    icon: Symbols.sell_sharp,
    label: 'Gym',
    route: AppRoutes.memberships,
  ),
  NavSection(
    icon: Symbols.bolt_sharp,
    label: 'Member App',
    railLabel: 'Member\nApp',
    route: AppRoutes.memberAppPreview,
  ),
  NavSection(
    icon: Symbols.point_of_sale_sharp,
    label: 'Kiosk Mode',
    railLabel: 'Kiosk\nMode',
    action: NavSectionAction.enterKiosk,
  ),
  NavSection(
    icon: Symbols.settings_sharp,
    label: 'Settings',
    route: AppRoutes.settings,
  ),
];

/// [kNavSections] filtered to what [role] may see, driving both the desktop
/// rail and the mobile dropdown so a role never renders a nav item it can't
/// open. The two routeless flow-opening entries each gate on their OWN
/// capability — "Add New Member" on [RolePolicy.canCreateMembers], "Kiosk Mode"
/// on [RolePolicy.canOperateKiosk] (kept distinct so restricting one never
/// hides the other); every routed entry shows iff the role may access its
/// route. A null [role] (pre-activation) hides everything — nav renders only
/// inside the activated workspace, where the role is always known.
List<NavSection> visibleNavSections(EmployeeRole? role) {
  bool isVisible(NavSection section) {
    final route = section.route;
    if (route != null) return role != null && role.canAccessRoute(route);
    // Routeless flow-opening item: gate on its action's own capability.
    switch (section.action) {
      case NavSectionAction.addMember:
        return role?.canCreateMembers ?? false;
      case NavSectionAction.enterKiosk:
        return role?.canOperateKiosk ?? false;
      case null:
        return false;
    }
  }

  return kNavSections.where(isVisible).toList();
}
