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
}
