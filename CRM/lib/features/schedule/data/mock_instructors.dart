import 'package:flutter/foundation.dart';

/// Mock instructors for the Schedule prototype.
///
/// Field names mirror the `gym_employees` table (first_name, last_name,
/// employee_pic_url, employee_type) so the future swap to a repository is
/// mechanical. No bundled instructor photos exist yet, so [photoAsset] is
/// left null and avatars fall back to initials.

/// Staff role on `gym_employees.employee_type`. The API hands these to us
/// lowercase; [label] capitalizes for display.
enum EmployeeType {
  owner,
  admin,
  trainer,
  unknown;

  String get label {
    switch (this) {
      case EmployeeType.owner:
        return 'Owner';
      case EmployeeType.admin:
        return 'Admin';
      case EmployeeType.trainer:
        return 'Trainer';
      case EmployeeType.unknown:
        return 'Staff';
    }
  }
}

@immutable
class Instructor {
  final String employeeId;
  final String firstName;
  final String lastName;
  final String? photoAsset;
  final EmployeeType employeeType;

  const Instructor({
    required this.employeeId,
    required this.firstName,
    required this.lastName,
    this.photoAsset,
    this.employeeType = EmployeeType.trainer,
  });

  String get fullName => '$firstName $lastName';
}

const Instructor kInstructorJustin = Instructor(
  employeeId: 'emp_001',
  firstName: 'Justin',
  lastName: 'Stemmons',
  employeeType: EmployeeType.owner,
);

const Instructor kInstructorAmy = Instructor(
  employeeId: 'emp_002',
  firstName: 'Amy',
  lastName: 'Traver',
);

const Instructor kInstructorBen = Instructor(
  employeeId: 'emp_003',
  firstName: 'Ben',
  lastName: 'Ama',
);

const Instructor kInstructorLily = Instructor(
  employeeId: 'emp_004',
  firstName: 'Lily',
  lastName: 'Altega',
);

const Instructor kInstructorSylvia = Instructor(
  employeeId: 'emp_005',
  firstName: 'Sylvia',
  lastName: 'Crivia',
  employeeType: EmployeeType.admin,
);

const Instructor kInstructorTimothy = Instructor(
  employeeId: 'emp_006',
  firstName: 'Timothy',
  lastName: 'Tom',
);

const List<Instructor> kMockInstructors = [
  kInstructorJustin,
  kInstructorAmy,
  kInstructorBen,
  kInstructorLily,
  kInstructorSylvia,
  kInstructorTimothy,
];
