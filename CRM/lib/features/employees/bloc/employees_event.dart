import 'package:equatable/equatable.dart';

import 'package:crm/core/auth/employee_role.dart';
import 'package:crm/features/employees/data/models/employee_create_request.dart';
import 'package:crm/features/employees/data/models/employee_update_request.dart';

/// Events for the [EmployeesBloc].
sealed class EmployeesEvent extends Equatable {
  const EmployeesEvent();

  @override
  List<Object?> get props => [];
}

/// Initial load — the roster (fatal) plus the gym's classes (non-fatal, used
/// only to derive per-employee teaching counts).
class EmployeesInitRequested extends EmployeesEvent {
  final String gymId;

  const EmployeesInitRequested(this.gymId);

  @override
  List<Object?> get props => [gymId];
}

/// Client-side name/role search changed (debounced).
class EmployeesSearchChanged extends EmployeesEvent {
  final String query;

  const EmployeesSearchChanged(this.query);

  @override
  List<Object?> get props => [query];
}

/// Role filter pill changed — `null` is the "All" pill.
class EmployeesRoleFilterChanged extends EmployeesEvent {
  final EmployeeRole? role;

  const EmployeesRoleFilterChanged(this.role);

  @override
  List<Object?> get props => [role];
}

/// Add-employee form submitted (rides the dedicated invite success channel).
class EmployeeInviteSubmitted extends EmployeesEvent {
  final EmployeeCreateRequest request;

  const EmployeeInviteSubmitted(this.request);

  @override
  List<Object?> get props => [request];
}

/// Edit-employee form submitted with only the changed fields.
class EmployeeUpdateSubmitted extends EmployeesEvent {
  final String employeeId;
  final EmployeeUpdateData data;

  const EmployeeUpdateSubmitted(this.employeeId, this.data);

  @override
  List<Object?> get props => [employeeId, data];
}

/// Remove-employee confirmed.
class EmployeeRemoveRequested extends EmployeesEvent {
  final String employeeId;

  const EmployeeRemoveRequested(this.employeeId);

  @override
  List<Object?> get props => [employeeId];
}

/// Re-send the staff onboarding email to a roster row whose invite is still
/// pending. Writes nothing to the row — the backend caps it at three sends per
/// person per hour.
class EmployeeInviteResendRequested extends EmployeesEvent {
  final String employeeId;

  const EmployeeInviteResendRequested(this.employeeId);

  @override
  List<Object?> get props => [employeeId];
}

/// Clears the last resend outcome / error once the list has shown it, so the
/// same snackbar never fires twice.
class EmployeesResendOutcomeCleared extends EmployeesEvent {
  const EmployeesResendOutcomeCleared();
}

/// Clears any lingering `mutationError` — dispatched by a dialog on open so a
/// stale failure never flashes (mirrors the charge dialog's outcome-clear).
class EmployeesMutationOutcomeCleared extends EmployeesEvent {
  const EmployeesMutationOutcomeCleared();
}
