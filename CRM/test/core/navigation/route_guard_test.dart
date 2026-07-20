import 'package:flutter_test/flutter_test.dart';

import 'package:crm/core/auth/employee_role.dart';
import 'package:crm/core/auth/role_policy.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/core/navigation/route_guard.dart';

void main() {
  group('redirectRouteFor', () {
    test('a null role passes through (pre-activation) — returns null', () {
      expect(redirectRouteFor(AppRoutes.growth, null), isNull);
    });

    test('a null path passes through — returns null', () {
      expect(redirectRouteFor(null, EmployeeRole.trainer), isNull);
    });

    test('a forbidden path redirects to that role\'s landing route', () {
      expect(
        redirectRouteFor(AppRoutes.growth, EmployeeRole.trainer),
        EmployeeRole.trainer.landingRoute,
      );
      // Front desk gets a READ-ONLY catalog: a catalog EDITOR deep-link
      // redirects to their landing route (they can't reach an editor).
      expect(
        redirectRouteFor(
          AppRoutes.membershipsRankEditor,
          EmployeeRole.frontDesk,
        ),
        EmployeeRole.frontDesk.landingRoute,
      );
      // Trainer may not view the catalog at all.
      expect(
        redirectRouteFor(AppRoutes.memberships, EmployeeRole.trainer),
        EmployeeRole.trainer.landingRoute,
      );
      expect(
        redirectRouteFor(AppRoutes.settings, EmployeeRole.trainer),
        EmployeeRole.trainer.landingRoute,
      );
    });

    test('an allowed path returns null (no redirect)', () {
      expect(
        redirectRouteFor(AppRoutes.schedule, EmployeeRole.trainer),
        isNull,
      );
      expect(
        redirectRouteFor(AppRoutes.members, EmployeeRole.frontDesk),
        isNull,
      );
      // Front desk reaches the catalog VIEW tabs, the rank DETAIL view, and
      // the Dashboard.
      expect(
        redirectRouteFor(AppRoutes.memberships, EmployeeRole.frontDesk),
        isNull,
      );
      expect(
        redirectRouteFor(
          AppRoutes.membershipsRankDetail,
          EmployeeRole.frontDesk,
        ),
        isNull,
      );
      expect(
        redirectRouteFor(AppRoutes.home, EmployeeRole.frontDesk),
        isNull,
      );
      expect(
        redirectRouteFor(AppRoutes.home, EmployeeRole.owner),
        isNull,
      );
    });

    test(
      'a path carrying a query string is normalized (stripped) before the '
      'access check — the employees table pushes /employees/detail?id=...',
      () {
        // Front desk may not manage staff, so the normalized bare path
        // (/employees/detail) is still correctly rejected.
        expect(
          redirectRouteFor('/employees/detail?id=x', EmployeeRole.frontDesk),
          EmployeeRole.frontDesk.landingRoute,
        );
        // Owner may manage staff, so the normalized path is allowed — the
        // query string does not confuse the guard into rejecting it.
        expect(
          redirectRouteFor('/employees/detail?id=x', EmployeeRole.owner),
          isNull,
        );
      },
    );
  });
}
