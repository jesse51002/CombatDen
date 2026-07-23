import 'package:json_annotation/json_annotation.dart';

import 'package:crm/core/auth/employee_role.dart';

part 'employee_create_request.g.dart';

/// POST body for creating a gym staff member. Mirrors the backend
/// `EmployeeCreateRequest`.
///
/// [employeeType] serializes to its snake-case backend string and may never
/// be `owner` (the picker offers only admin/front_desk/trainer). [email] is
/// required — every UI-added employee gets an email-based login path.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
  createToJson: true,
  includeIfNull: false,
)
class EmployeeCreateRequest {
  @JsonKey(toJson: _roleToJson)
  final EmployeeRole employeeType;
  final String firstName;
  final String lastName;
  final String email;
  final String? phone;
  final String? employeePublicDescription;

  const EmployeeCreateRequest({
    required this.employeeType,
    required this.firstName,
    required this.lastName,
    required this.email,
    this.phone,
    this.employeePublicDescription,
  });

  Map<String, dynamic> toJson() => _$EmployeeCreateRequestToJson(this);
}

String _roleToJson(EmployeeRole role) => role.value;
