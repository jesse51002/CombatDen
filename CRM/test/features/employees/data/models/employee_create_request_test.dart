import 'package:flutter_test/flutter_test.dart';

import 'package:crm/core/auth/employee_role.dart';
import 'package:crm/features/employees/data/models/employee_create_request.dart';

/// `send_invite` is REQUIRED by the backend with no default, so a body that
/// omits it is a 422 on every employee create. The field is serialized by
/// `json_serializable`, which means adding it to the Dart class is NOT enough
/// — the `.g.dart` has to be regenerated, and nothing but a test like this
/// catches a stale one (the analyzer is perfectly happy either way).
void main() {
  EmployeeCreateRequest request({required bool sendInvite}) =>
      EmployeeCreateRequest(
        employeeType: EmployeeRole.trainer,
        firstName: 'New',
        lastName: 'Hire',
        email: 'new.hire@example.com',
        sendInvite: sendInvite,
      );

  test('the wire body always carries send_invite', () {
    expect(request(sendInvite: true).toJson()['send_invite'], isTrue);
    expect(request(sendInvite: false).toJson()['send_invite'], isFalse);
  });

  test('the rest of the create body is unchanged', () {
    expect(request(sendInvite: true).toJson(), {
      'employee_type': 'trainer',
      'first_name': 'New',
      'last_name': 'Hire',
      'email': 'new.hire@example.com',
      'send_invite': true,
    });
  });
}
