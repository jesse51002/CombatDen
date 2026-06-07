/// The caller's role at a gym, from `gym_employees.employee_type`.
///
/// Mirrors the backend enum. `unknown` is a safe fallback for
/// forward-compatibility when the backend introduces a new value.
enum EmployeeRole {
  owner('owner'),
  admin('admin'),
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
}
