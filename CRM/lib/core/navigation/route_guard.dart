import 'package:crm/core/auth/employee_role.dart';
import 'package:crm/core/auth/role_policy.dart';

/// Pure route-access guard shared by `main.dart`'s `_onGenerateRoute` and the
/// auth gate's initial-route resolution.
///
/// Returns the landing route to redirect to when [role] may not access
/// [path], or `null` when access is allowed (or there is nothing to gate).
/// A null [role] (pre-activation) or null [path] passes through — gating only
/// applies once a gym is active and a concrete path is known.
String? redirectRouteFor(String? path, EmployeeRole? role) {
  if (role == null || path == null) return null;
  // Strip any query string / fragment so the guard sees the bare path (the
  // employees table pushes `/employees/detail?id=...`).
  final normalized = Uri.parse(path).path;
  return role.canAccessRoute(normalized) ? null : role.landingRoute;
}
