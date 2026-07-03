import 'package:flutter/material.dart';

import 'package:crm/core/state/theme_controller.dart';
import 'package:crm/features/gym_setup/data/models/employee_role.dart';

/// One item from `GET /api/v1/gyms/` — a gym the signed-in user
/// owns or admins, annotated with the caller's [role] for it.
///
/// The auth gate lists these after sign-in to choose the active
/// gym (one gym → straight in; several → the gym picker). The
/// chosen gym's [gymId] (a real UUID) then scopes every CRM member
/// query, and [themePreference] (the caller's saved CRM appearance
/// for that gym) hydrates the theme. [logoUrl] (the gym's uploaded
/// brand logo, nullable — null means none) seeds the nav chrome and
/// the Gym profile editor.
class GymWithRole {
  final String gymId;
  final String gymName;
  final String? gymDescription;
  final String? logoUrl;
  final String timezone;
  final EmployeeRole role;
  final ThemeMode themePreference;

  const GymWithRole({
    required this.gymId,
    required this.gymName,
    required this.timezone,
    required this.role,
    required this.themePreference,
    this.gymDescription,
    this.logoUrl,
  });

  factory GymWithRole.fromJson(Map<String, dynamic> json) {
    return GymWithRole(
      gymId: json['gym_id'] as String,
      gymName: json['gym_name'] as String,
      gymDescription: json['gym_description'] as String?,
      logoUrl: json['logo_url'] as String?,
      timezone: json['timezone'] as String,
      role: EmployeeRole.fromJson(json['employee_type'] as String),
      themePreference:
          themeModeFromApi(json['theme_preference'] as String?),
    );
  }
}
