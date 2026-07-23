import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/core/auth/employee_role.dart';
import 'package:crm/features/employees/data/models/invite_status.dart';

part 'employee.g.dart';

/// A gym staff member — one `gym_employees` row plus its API-derived
/// [inviteStatus]. Mirrors the backend `EmployeeResponse`
/// (`../FastApiBackend/src/employees/schema/employees_schema.py`)
/// field-for-field.
///
/// Identity is the (lowercased) [email] — a verified Supabase account whose
/// email matches is that person's login; there is no user id. An email-less
/// row is an instructor's data (never a login principal), surfaced as
/// [InviteStatus.none]. [employeeType] parses through the app-wide
/// [EmployeeRole]; [inviteStatus] through [InviteStatus] — both resilient.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class Employee extends Equatable {
  final String employeeId;
  final String gymId;

  @JsonKey(fromJson: EmployeeRole.fromJson)
  final EmployeeRole employeeType;

  final String firstName;
  final String lastName;
  final String? phone;
  final String? email;
  final String? employeePicUrl;
  final String? employeePublicDescription;
  final DateTime createdAt;

  @JsonKey(fromJson: InviteStatus.fromJson)
  final InviteStatus inviteStatus;

  const Employee({
    required this.employeeId,
    required this.gymId,
    required this.employeeType,
    required this.firstName,
    required this.lastName,
    this.phone,
    this.email,
    this.employeePicUrl,
    this.employeePublicDescription,
    required this.createdAt,
    required this.inviteStatus,
  });

  factory Employee.fromJson(Map<String, dynamic> json) =>
      _$EmployeeFromJson(json);

  /// `First Last` for display.
  String get fullName => '$firstName $lastName';

  @override
  List<Object?> get props => [
        employeeId,
        gymId,
        employeeType,
        firstName,
        lastName,
        phone,
        email,
        employeePicUrl,
        employeePublicDescription,
        createdAt,
        inviteStatus,
      ];
}
