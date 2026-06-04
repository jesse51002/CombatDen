import 'package:crm/features/gym_setup/data/models/employee_role.dart';

/// One item from `GET /api/v1/gyms/` — a gym the signed-in user
/// owns or admins, annotated with the caller's [role] for it.
///
/// The auth gate lists these after sign-in to choose the active
/// gym (one gym → straight in; several → the gym picker). The
/// chosen gym's [gymId] (a real UUID) then scopes every CRM member
/// query.
class GymWithRole {
  final String gymId;
  final String gymName;
  final String? gymDescription;
  final String timezone;
  final EmployeeRole role;

  const GymWithRole({
    required this.gymId,
    required this.gymName,
    required this.timezone,
    required this.role,
    this.gymDescription,
  });

  factory GymWithRole.fromJson(Map<String, dynamic> json) {
    return GymWithRole(
      gymId: json['gym_id'] as String,
      gymName: json['gym_name'] as String,
      gymDescription: json['gym_description'] as String?,
      timezone: json['timezone'] as String,
      role: EmployeeRole.fromJson(json['employee_type'] as String),
    );
  }
}
