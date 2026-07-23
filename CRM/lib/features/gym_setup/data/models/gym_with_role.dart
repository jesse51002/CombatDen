import 'package:flutter/material.dart';

import 'package:crm/core/auth/employee_role.dart';
import 'package:crm/core/state/theme_controller.dart';

/// One item from `GET /api/v1/gyms/` — a gym the signed-in user
/// owns or admins, annotated with the caller's [role] for it.
///
/// The auth gate lists these after sign-in to choose the active
/// gym (one gym → straight in; several → the gym picker). The
/// chosen gym's [gymId] (a real UUID) then scopes every CRM member
/// query, [themePreference] (the caller's saved CRM appearance for
/// that gym) hydrates the admin app's light/dark mode,
/// [themeDesignId] (the gym's saved ThemeService design) seeds the
/// Theme-tab preview, and [logoUrl] (the gym's uploaded brand logo,
/// nullable — null means none) seeds the nav chrome and the Gym
/// profile editor.
class GymWithRole {
  final String gymId;
  final String gymName;
  final String? gymDescription;
  final String? logoUrl;
  final String timezone;
  final EmployeeRole role;
  final ThemeMode themePreference;

  /// The gym's persisted ThemeService design id (`gyms.theme_design_id`);
  /// null until a theme is chosen. Seeds the Theme tab so it boots on the
  /// gym's saved branding.
  final String? themeDesignId;

  /// When the gym was created (`gyms.created_at`); null on an older backend
  /// that doesn't yet return the field. The Settings → Reports & exports
  /// month picker floors its year list at this year (falling back to a fixed
  /// year when null).
  final DateTime? createdAt;

  const GymWithRole({
    required this.gymId,
    required this.gymName,
    required this.timezone,
    required this.role,
    required this.themePreference,
    this.gymDescription,
    this.themeDesignId,
    this.logoUrl,
    this.createdAt,
  });

  factory GymWithRole.fromJson(Map<String, dynamic> json) {
    final createdAtRaw = json['created_at'] as String?;
    return GymWithRole(
      gymId: json['gym_id'] as String,
      gymName: json['gym_name'] as String,
      gymDescription: json['gym_description'] as String?,
      logoUrl: json['logo_url'] as String?,
      timezone: json['timezone'] as String,
      role: EmployeeRole.fromJson(json['employee_type'] as String),
      themePreference:
          themeModeFromApi(json['theme_preference'] as String?),
      themeDesignId: json['theme_design_id'] as String?,
      createdAt: createdAtRaw == null ? null : DateTime.tryParse(createdAtRaw),
    );
  }
}
