import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/navigation/app_routes.dart';

/// One entry in the app's primary navigation, shared by the desktop rail
/// ([SectionsBar]) and the mobile dropdown ([SectionsMobileMenu]) so both
/// render the exact same items in the same order — change the nav once, here.
///
/// [route] is `null` only for the primary "Add New Member" CTA (not wired yet);
/// the chrome renders that as a no-op. Every other item navigates.
class NavSection {
  final IconData icon;

  /// Flat, single-line label — used by the mobile dropdown rows.
  final String label;

  /// The rail's hand-tuned label, which may carry a deliberate `\n` line break
  /// (e.g. `'Member\nApp'`) so two-word items wrap cleanly in the narrow rail.
  /// Falls back to [label] when the rail label is identical.
  final String? railLabel;

  /// Target route, or `null` for a not-yet-wired no-op item.
  final String? route;

  /// The always-sapphire primary CTA ("Add New Member") — painted like the
  /// active item but without the active accent bar.
  final bool isPrimary;

  const NavSection({
    required this.icon,
    required this.label,
    this.railLabel,
    this.route,
    this.isPrimary = false,
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
    icon: Symbols.settings_sharp,
    label: 'Settings',
    route: AppRoutes.settings,
  ),
];
