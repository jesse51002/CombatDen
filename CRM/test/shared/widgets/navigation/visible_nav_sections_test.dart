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
      'front desk sees exactly the Add New Member CTA, People, Schedule, '
      'and Settings — Dashboard, Growth, Gym, and Member App are hidden',
      () {
        final routes =
            visibleNavSections(EmployeeRole.frontDesk).map((s) => s.route);
        expect(
          routes,
          [null, AppRoutes.members, AppRoutes.schedule, AppRoutes.settings],
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
