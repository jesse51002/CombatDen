import 'package:json_annotation/json_annotation.dart';

import 'package:crm/core/auth/employee_role.dart';

part 'employee_update_request.g.dart';

/// The mutable employee fields — all optional. Only changed fields are sent
/// (`includeIfNull: false`); an omitted field means "leave unchanged" (this
/// endpoint never clears a field to NULL). [employeeType] serializes to its
/// snake-case string and may never be set to `owner`. Mirrors the backend
/// `EmployeeUpdateData`.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createFactory: false,
  createToJson: true,
  includeIfNull: false,
)
class EmployeeUpdateData {
  final String? firstName;
  final String? lastName;
  final String? phone;
  final String? email;
  final String? employeePublicDescription;
  final String? employeePicUrl;
  @JsonKey(toJson: _roleOrNullToJson)
  final EmployeeRole? employeeType;

  const EmployeeUpdateData({
    this.firstName,
    this.lastName,
    this.phone,
    this.email,
    this.employeePublicDescription,
    this.employeePicUrl,
    this.employeeType,
  });

  Map<String, dynamic> toJson() => _$EmployeeUpdateDataToJson(this);

  /// True when at least one field is set — the edit dialog skips a no-op save.
  /// A computed helper, never serialized.
  @JsonKey(includeToJson: false)
  bool get hasChanges =>
      firstName != null ||
      lastName != null ||
      phone != null ||
      email != null ||
      employeePublicDescription != null ||
      employeePicUrl != null ||
      employeeType != null;
}

/// Wraps [EmployeeUpdateData] as `{data: {...}}` — the project update-request
/// convention (identity lives in the URL path; the body carries only the
/// mutable `data`). Mirrors the backend `EmployeeUpdateRequest`. The nested
/// serialization is explicit (not left to `jsonEncode`'s `toEncodable`).
class EmployeeUpdateRequest {
  final EmployeeUpdateData data;

  const EmployeeUpdateRequest({required this.data});

  Map<String, dynamic> toJson() => {'data': data.toJson()};
}

String? _roleOrNullToJson(EmployeeRole? role) => role?.value;
