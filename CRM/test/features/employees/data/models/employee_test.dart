import 'package:flutter_test/flutter_test.dart';

import 'package:crm/core/auth/employee_role.dart';
import 'package:crm/features/employees/data/models/employee.dart';
import 'package:crm/features/employees/data/models/employee_taught_class.dart';
import 'package:crm/features/employees/data/models/invite_status.dart';
import 'package:crm/features/schedule/data/class_time_format.dart';
import 'package:crm/features/schedule/data/models/class_slot.dart';
import 'package:crm/features/schedule/data/models/gym_class_response.dart';
import 'package:crm/features/schedule/data/models/recurring_unit.dart';

Map<String, dynamic> _employeeJson({
  String employeeType = 'admin',
  String? email = 'jane@example.com',
  String? phone = '555-1234',
  String? employeePicUrl = 'https://cdn.combatden.net/pic.png',
  String inviteStatus = 'active',
}) => {
      'employee_id': 'emp-1',
      'gym_id': 'gym-1',
      'employee_type': employeeType,
      'first_name': 'Jane',
      'last_name': 'Doe',
      'phone': phone,
      'email': email,
      'employee_pic_url': employeePicUrl,
      'employee_public_description': 'Head coach',
      'created_at': '2026-01-01T00:00:00.000Z',
      'invite_status': inviteStatus,
    };

GymClassResponse _classFixture({
  required String classId,
  required String className,
  required Map<String, List<ClassSlot>> weekdaySlots,
  RecurringUnit recurringUnit = RecurringUnit.weekly,
  int recurringInterval = 1,
}) {
  return GymClassResponse(
    classId: classId,
    gymId: 'gym-1',
    className: className,
    durationMinutes: 60,
    recurringUnit: recurringUnit,
    recurringInterval: recurringInterval,
    weekdaySlots: weekdaySlots,
    startDate: DateTime(2026, 1, 1),
    pointsWorth: 10,
    isActive: true,
    isDeleted: false,
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  group('Employee.fromJson', () {
    test('parses a full row', () {
      final employee = Employee.fromJson(_employeeJson());

      expect(employee.employeeId, 'emp-1');
      expect(employee.gymId, 'gym-1');
      expect(employee.employeeType, EmployeeRole.admin);
      expect(employee.firstName, 'Jane');
      expect(employee.lastName, 'Doe');
      expect(employee.phone, '555-1234');
      expect(employee.email, 'jane@example.com');
      expect(
        employee.employeePicUrl,
        'https://cdn.combatden.net/pic.png',
      );
      expect(employee.employeePublicDescription, 'Head coach');
      expect(
        employee.createdAt,
        DateTime.parse('2026-01-01T00:00:00.000Z'),
      );
      expect(employee.inviteStatus, InviteStatus.active);
      expect(employee.fullName, 'Jane Doe');
    });

    test('nullable email/phone/pic parse as null', () {
      final employee = Employee.fromJson(
        _employeeJson(email: null, phone: null, employeePicUrl: null),
      );

      expect(employee.email, isNull);
      expect(employee.phone, isNull);
      expect(employee.employeePicUrl, isNull);
    });

    test(
      'an unrecognized invite_status falls back to InviteStatus.unknown '
      '(resilient enum parsing)',
      () {
        final employee = Employee.fromJson(
          _employeeJson(inviteStatus: 'brand_new_status'),
        );
        expect(employee.inviteStatus, InviteStatus.unknown);
      },
    );

    test(
      'an unrecognized employee_type falls back to EmployeeRole.unknown '
      '(resilient enum parsing)',
      () {
        final employee = Employee.fromJson(
          _employeeJson(employeeType: 'super_admin'),
        );
        expect(employee.employeeType, EmployeeRole.unknown);
      },
    );
  });

  group('EmployeeTaughtClass.deriveByInstructor', () {
    test(
      'groups weekly slots by instructor id; a class with no matching '
      'instructor is absent from the result entirely',
      () {
        final boxing = _classFixture(
          classId: 'class-boxing',
          className: 'Boxing',
          weekdaySlots: {
            'mon': [const ClassSlot(time: '18:00:00', instructorId: 'emp-1')],
            'wed': [const ClassSlot(time: '18:00:00', instructorId: 'emp-1')],
          },
        );
        final yoga = _classFixture(
          classId: 'class-yoga',
          className: 'Yoga',
          weekdaySlots: {
            'tue': [const ClassSlot(time: '09:00:00', instructorId: 'emp-2')],
          },
        );
        // No instructor assigned to this slot — must not create a bucket.
        final openMat = _classFixture(
          classId: 'class-open-mat',
          className: 'Open Mat',
          weekdaySlots: {
            'fri': [const ClassSlot(time: '20:00:00')],
          },
        );

        final result = EmployeeTaughtClass.deriveByInstructor(
          [boxing, yoga, openMat],
        );

        expect(result.keys.toSet(), {'emp-1', 'emp-2'});

        expect(result['emp-1'], hasLength(1));
        final boxingForEmp1 = result['emp-1']!.single;
        expect(boxingForEmp1.className, 'Boxing');
        expect(boxingForEmp1.cadenceLabel, 'Weekly');
        final mondayLabel = classTimeRangeLabel('18:00:00', 60);
        expect(boxingForEmp1.slotLabels, [
          'Mon · $mondayLabel',
          'Wed · $mondayLabel',
        ]);

        expect(result['emp-2'], hasLength(1));
        expect(result['emp-2']!.single.className, 'Yoga');

        // "Open Mat" never appears anywhere — it had no instructor.
        final allTaughtClassNames =
            result.values.expand((list) => list).map((c) => c.className);
        expect(allTaughtClassNames, isNot(contains('Open Mat')));
      },
    );

    test(
      'a single instructor teaching multiple classes gets them sorted '
      'case-insensitively by class name',
      () {
        final zumba = _classFixture(
          classId: 'class-zumba',
          className: 'Zumba',
          weekdaySlots: {
            'mon': [const ClassSlot(time: '10:00:00', instructorId: 'emp-3')],
          },
        );
        final abBlast = _classFixture(
          classId: 'class-ab-blast',
          className: 'ab blast',
          weekdaySlots: {
            'tue': [const ClassSlot(time: '11:00:00', instructorId: 'emp-3')],
          },
        );

        final result =
            EmployeeTaughtClass.deriveByInstructor([zumba, abBlast]);

        expect(
          result['emp-3']!.map((c) => c.className),
          ['ab blast', 'Zumba'],
        );
      },
    );

    test('daily cadence with an interval > 1 reads "Every N days"', () {
      final openGym = _classFixture(
        classId: 'class-open-gym',
        className: 'Open Gym',
        recurringUnit: RecurringUnit.daily,
        recurringInterval: 3,
        weekdaySlots: {
          'all': [const ClassSlot(time: '06:00:00', instructorId: 'emp-4')],
        },
      );

      final result = EmployeeTaughtClass.deriveByInstructor([openGym]);

      expect(result['emp-4']!.single.cadenceLabel, 'Every 3 days');
      // The reserved "all" key carries no weekday prefix.
      expect(
        result['emp-4']!.single.slotLabels,
        [classTimeRangeLabel('06:00:00', 60)],
      );
    });
  });
}
