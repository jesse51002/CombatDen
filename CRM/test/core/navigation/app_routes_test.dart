import 'package:crm/core/navigation/app_routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppRoutes member-detail deep link', () {
    test('memberDetailPath builds /members/detail/<id>', () {
      expect(
        AppRoutes.memberDetailPath('abc-123'),
        '/members/detail/abc-123',
      );
    });

    test('memberIdFromPath extracts the id', () {
      expect(
        AppRoutes.memberIdFromPath('/members/detail/abc-123'),
        'abc-123',
      );
    });

    test('memberIdFromPath round-trips memberDetailPath', () {
      const id = 'a1b2c3d4-0000-uuid-9999';
      expect(
        AppRoutes.memberIdFromPath(AppRoutes.memberDetailPath(id)),
        id,
      );
    });

    test('the bare detail route carries no id', () {
      expect(
        AppRoutes.memberIdFromPath(AppRoutes.memberDetail),
        isNull,
      );
      expect(
        AppRoutes.memberIdFromPath('/members/detail/'),
        isNull,
      );
    });

    test('a non-detail route carries no id', () {
      expect(AppRoutes.memberIdFromPath(AppRoutes.members), isNull);
      expect(AppRoutes.memberIdFromPath('/schedule'), isNull);
      expect(AppRoutes.memberIdFromPath('/'), isNull);
    });
  });

  group('AppRoutes employee-detail deep link', () {
    test('employeeDetailPath builds /employees/detail/<id>', () {
      expect(
        AppRoutes.employeeDetailPath('emp-123'),
        '/employees/detail/emp-123',
      );
    });

    test('employeeIdFromPath extracts the id', () {
      expect(
        AppRoutes.employeeIdFromPath('/employees/detail/emp-123'),
        'emp-123',
      );
    });

    test('employeeIdFromPath round-trips employeeDetailPath', () {
      const id = 'e1f2g3h4-0000-uuid-8888';
      expect(
        AppRoutes.employeeIdFromPath(AppRoutes.employeeDetailPath(id)),
        id,
      );
    });

    test('the bare detail route carries no id', () {
      expect(
        AppRoutes.employeeIdFromPath(AppRoutes.employeeDetail),
        isNull,
      );
      expect(
        AppRoutes.employeeIdFromPath('/employees/detail/'),
        isNull,
      );
    });

    test('a non-detail route carries no id', () {
      expect(AppRoutes.employeeIdFromPath(AppRoutes.employees), isNull);
      expect(AppRoutes.employeeIdFromPath('/schedule'), isNull);
      expect(AppRoutes.employeeIdFromPath('/'), isNull);
      // Not swallowed by the member-detail round-trip helpers either.
      expect(
        AppRoutes.employeeIdFromPath(AppRoutes.memberDetailPath('m1')),
        isNull,
      );
    });
  });
}
