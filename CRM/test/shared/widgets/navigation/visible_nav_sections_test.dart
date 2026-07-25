import 'package:flutter_test/flutter_test.dart';

import 'package:crm/core/auth/employee_role.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/shared/widgets/navigation/nav_sections.dart';

void main() {
  group('visibleNavSections', () {
    test(
      'a null role (pre-activation) hides every section, including the '
      'routeless Add New Member CTA',
      () {
        expect(visibleNavSections(null), isEmpty);
      },
    );

    test('owner sees every nav section, in the declared order', () {
      final routes =
          visibleNavSections(EmployeeRole.owner).map((s) => s.route);
      expect(routes, kNavSections.map((s) => s.route));
    });

    test('admin sees every nav section too (same access as owner)', () {
      final routes =
          visibleNavSections(EmployeeRole.admin).map((s) => s.route);
      expect(routes, kNavSections.map((s) => s.route));
    });

    test(
      'front desk sees the Add New Member CTA, Dashboard, People, Schedule, '
      'Gym, Kiosk Mode, and Settings — Growth and Member App are hidden',
      () {
        final sections = visibleNavSections(EmployeeRole.frontDesk);
        // Two routeless items (route == null) are visible — Add New Member
        // (canCreateMembers) and Kiosk Mode (canOperateKiosk) — so assert on
        // the unique labels, which the route map cannot disambiguate.
        expect(
          sections.map((s) => s.label),
          [
            'Add New Member',
            'Dashboard',
            'People',
            'Schedule',
            'Gym',
            'Kiosk Mode',
            'Settings',
          ],
        );
      },
    );

    test(
      'trainer (read-only) sees only Schedule — every other section, '
      'including the Add New Member CTA, is hidden',
      () {
        final routes =
            visibleNavSections(EmployeeRole.trainer).map((s) => s.route);
        expect(routes, [AppRoutes.schedule]);
      },
    );

    test(
      'unknown (forward-compat fallback) matches trainer: Schedule only',
      () {
        final routes =
            visibleNavSections(EmployeeRole.unknown).map((s) => s.route);
        expect(routes, [AppRoutes.schedule]);
      },
    );
  });
}
