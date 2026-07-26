import 'package:equatable/equatable.dart';

import 'package:crm/core/auth/employee_role.dart';
import 'package:crm/features/emails/data/models/invite_outcome.dart';
import 'package:crm/features/employees/data/models/employee.dart';
import 'package:crm/features/employees/data/models/employee_taught_class.dart';

/// States for the [EmployeesBloc].
sealed class EmployeesState extends Equatable {
  const EmployeesState();

  @override
  List<Object?> get props => [];
}

/// Before any load.
class EmployeesInitial extends EmployeesState {
  const EmployeesInitial();
}

/// Fetching the first roster page.
class EmployeesLoading extends EmployeesState {
  const EmployeesLoading();
}

/// Roster loaded.
///
/// [employees] is the full roster; [visibleEmployees] is it filtered by
/// [query] + [roleFilter] (derived on every change). [taughtByEmployeeId] maps
/// an employee id → the classes they teach (empty when [classesLoadFailed]).
///
/// Each mutation rides its own **monotonic success token**
/// ([inviteSuccess] / [updateSuccess] / [removeSuccess]) that a dialog
/// snapshots at open and watches for an increment — the charge-card terminal
/// pattern, so the dialog's own success step fires against committed state, not
/// "request sent". A failure sets [mutationError] instead. [lastInvitedEmployee]
/// is the row the most recent invite created (its stored, lowercased email
/// backs the Add dialog's copyable sign-in instructions) and
/// [lastInviteOutcome] is what the backend actually did about that person's
/// invite, so the success step never claims a send that didn't happen.
///
/// Resending an invite rides its OWN channel ([resendingEmployeeId] /
/// [resendToken] / [resendOutcome] / [resendError]) rather than the mutation
/// one: it changes no row, so it must not reload the roster or trip the
/// dialogs' shared [isMutating] flag.
class EmployeesLoaded extends EmployeesState {
  final String gymId;
  final List<Employee> employees;
  final String query;
  final EmployeeRole? roleFilter;
  final List<Employee> visibleEmployees;
  final Map<String, List<EmployeeTaughtClass>> taughtByEmployeeId;
  final bool classesLoadFailed;

  final int inviteSuccess;
  final int updateSuccess;
  final int removeSuccess;
  final Employee? lastInvitedEmployee;
  final InviteOutcome? lastInviteOutcome;

  /// The row whose invite resend is in flight — drives that row's inline busy
  /// state, and keeps a second resend from stacking on the first.
  final String? resendingEmployeeId;

  /// Monotonic token bumped once a resend settles (either way). The list
  /// watches it so the same outcome never fires two snackbars.
  final int resendToken;

  /// What the last resend actually did, or the error it failed with. Exactly
  /// one is non-null after a settled resend.
  final InviteOutcome? resendOutcome;
  final Object? resendError;

  final bool isMutating;
  final String? mutationError;

  const EmployeesLoaded({
    required this.gymId,
    required this.employees,
    required this.visibleEmployees,
    this.query = '',
    this.roleFilter,
    this.taughtByEmployeeId = const {},
    this.classesLoadFailed = false,
    this.inviteSuccess = 0,
    this.updateSuccess = 0,
    this.removeSuccess = 0,
    this.lastInvitedEmployee,
    this.lastInviteOutcome,
    this.resendingEmployeeId,
    this.resendToken = 0,
    this.resendOutcome,
    this.resendError,
    this.isMutating = false,
    this.mutationError,
  });

  EmployeesLoaded copyWith({
    String? gymId,
    List<Employee>? employees,
    String? query,
    EmployeeRole? roleFilter,
    bool clearRoleFilter = false,
    List<Employee>? visibleEmployees,
    Map<String, List<EmployeeTaughtClass>>? taughtByEmployeeId,
    bool? classesLoadFailed,
    int? inviteSuccess,
    int? updateSuccess,
    int? removeSuccess,
    Employee? lastInvitedEmployee,
    InviteOutcome? lastInviteOutcome,
    String? resendingEmployeeId,
    bool clearResendingEmployeeId = false,
    int? resendToken,
    InviteOutcome? resendOutcome,
    Object? resendError,
    bool clearResendOutcome = false,
    bool? isMutating,
    String? mutationError,
    bool clearMutationError = false,
  }) {
    return EmployeesLoaded(
      gymId: gymId ?? this.gymId,
      employees: employees ?? this.employees,
      query: query ?? this.query,
      roleFilter: clearRoleFilter ? null : (roleFilter ?? this.roleFilter),
      visibleEmployees: visibleEmployees ?? this.visibleEmployees,
      taughtByEmployeeId: taughtByEmployeeId ?? this.taughtByEmployeeId,
      classesLoadFailed: classesLoadFailed ?? this.classesLoadFailed,
      inviteSuccess: inviteSuccess ?? this.inviteSuccess,
      updateSuccess: updateSuccess ?? this.updateSuccess,
      removeSuccess: removeSuccess ?? this.removeSuccess,
      lastInvitedEmployee: lastInvitedEmployee ?? this.lastInvitedEmployee,
      lastInviteOutcome: lastInviteOutcome ?? this.lastInviteOutcome,
      resendingEmployeeId: clearResendingEmployeeId
          ? null
          : (resendingEmployeeId ?? this.resendingEmployeeId),
      resendToken: resendToken ?? this.resendToken,
      resendOutcome:
          clearResendOutcome ? null : (resendOutcome ?? this.resendOutcome),
      resendError:
          clearResendOutcome ? null : (resendError ?? this.resendError),
      isMutating: isMutating ?? this.isMutating,
      mutationError:
          clearMutationError ? null : (mutationError ?? this.mutationError),
    );
  }

  @override
  List<Object?> get props => [
        gymId,
        employees,
        query,
        roleFilter,
        visibleEmployees,
        taughtByEmployeeId,
        classesLoadFailed,
        inviteSuccess,
        updateSuccess,
        removeSuccess,
        lastInvitedEmployee,
        lastInviteOutcome,
        resendingEmployeeId,
        resendToken,
        resendOutcome,
        resendError,
        isMutating,
        mutationError,
      ];
}

/// The roster load failed (retryable).
class EmployeesError extends EmployeesState {
  final String message;
  final String gymId;

  const EmployeesError(this.message, {required this.gymId});

  @override
  List<Object?> get props => [message, gymId];
}
