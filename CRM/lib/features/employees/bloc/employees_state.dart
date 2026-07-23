import 'package:equatable/equatable.dart';

import 'package:crm/core/auth/employee_role.dart';
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
/// backs the Add dialog's copyable sign-in instructions).
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
