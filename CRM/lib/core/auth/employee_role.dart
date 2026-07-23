/// The caller's role at a gym, from `gym_employees.employee_type`.
///
/// The app-wide canonical role enum — every capability decision keys off it
/// (see `role_policy.dart`). Mirrors the backend enum. `unknown` is a safe
/// fallback for forward-compatibility when the backend introduces a new value.
enum EmployeeRole {
  owner('owner'),
  admin('admin'),
  frontDesk('front_desk'),
  trainer('trainer'),
  unknown('unknown');

  final String value;
  const EmployeeRole(this.value);

  static EmployeeRole fromJson(String value) {
    return EmployeeRole.values.firstWhere(
      (r) => r.value == value,
      orElse: () => EmployeeRole.unknown,
    );
  }

  /// Human-readable label for display (role chips, table cells). `unknown`
  /// reads as the generic "Staff" so an unrecognized backend value still
  /// shows something sensible.
  String get label {
    switch (this) {
      case EmployeeRole.owner:
        return 'Owner';
      case EmployeeRole.admin:
        return 'Admin';
      case EmployeeRole.frontDesk:
        return 'Front Desk';
      case EmployeeRole.trainer:
        return 'Trainer';
      case EmployeeRole.unknown:
        return 'Staff';
    }
  }
}
