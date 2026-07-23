import 'dart:async';
import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:stream_transform/stream_transform.dart';

import 'package:crm/core/auth/employee_role.dart';
import 'package:crm/core/errors/exceptions.dart';
import 'package:crm/features/employees/bloc/employees_event.dart';
import 'package:crm/features/employees/bloc/employees_state.dart';
import 'package:crm/features/employees/data/models/employee.dart';
import 'package:crm/features/employees/data/models/employee_taught_class.dart';
import 'package:crm/features/employees/data/repositories/employees_repository.dart';
import 'package:crm/features/schedule/data/models/gym_class_response.dart';
import 'package:crm/features/schedule/data/repositories/schedule_repository.dart';

EventTransformer<E> _debounce<E>(Duration duration) =>
    (events, mapper) => events.debounce(duration).switchMap(mapper);

/// BLoC for the Employees (staff roster) surface.
///
/// Loads the roster (fatal) alongside the gym's classes (non-fatal — only used
/// to derive each employee's teaching count). Search + role filter run
/// client-side against the loaded roster. Every mutation rides a dedicated
/// monotonic success token so the Add/Edit/Remove dialogs confirm against
/// committed state (the charge-card terminal pattern), never fire-and-pop.
class EmployeesBloc extends Bloc<EmployeesEvent, EmployeesState> {
  final EmployeesRepository _employeesRepository;
  final ScheduleRepository _scheduleRepository;

  EmployeesBloc({
    required EmployeesRepository employeesRepository,
    required ScheduleRepository scheduleRepository,
  })  : _employeesRepository = employeesRepository,
        _scheduleRepository = scheduleRepository,
        super(const EmployeesInitial()) {
    on<EmployeesInitRequested>(_onInitRequested);
    on<EmployeesSearchChanged>(
      _onSearchChanged,
      transformer: _debounce(const Duration(milliseconds: 300)),
    );
    on<EmployeesRoleFilterChanged>(_onRoleFilterChanged);
    on<EmployeeInviteSubmitted>(_onInviteSubmitted);
    on<EmployeeUpdateSubmitted>(_onUpdateSubmitted);
    on<EmployeeRemoveRequested>(_onRemoveRequested);
    on<EmployeesMutationOutcomeCleared>(_onMutationOutcomeCleared);
  }

  Future<void> _onInitRequested(
    EmployeesInitRequested event,
    Emitter<EmployeesState> emit,
  ) async {
    emit(const EmployeesLoading());
    // Classes load concurrently and are best-effort — a failure degrades the
    // teaching count to an em dash, never fails the roster.
    final classesFuture = _loadClasses(event.gymId);
    try {
      final employees =
          await _employeesRepository.listEmployees(event.gymId);
      final classes = await classesFuture;
      emit(EmployeesLoaded(
        gymId: event.gymId,
        employees: employees,
        visibleEmployees: employees,
        taughtByEmployeeId: classes.failed
            ? const {}
            : EmployeeTaughtClass.deriveByInstructor(classes.classes),
        classesLoadFailed: classes.failed,
      ));
    } catch (e, stackTrace) {
      log('Failed to load employees', error: e, stackTrace: stackTrace);
      emit(EmployeesError(e.toString(), gymId: event.gymId));
    }
  }

  Future<void> _onSearchChanged(
    EmployeesSearchChanged event,
    Emitter<EmployeesState> emit,
  ) async {
    final s = state;
    if (s is! EmployeesLoaded) return;
    emit(s.copyWith(
      query: event.query,
      visibleEmployees: _filter(s.employees, event.query, s.roleFilter),
    ));
  }

  Future<void> _onRoleFilterChanged(
    EmployeesRoleFilterChanged event,
    Emitter<EmployeesState> emit,
  ) async {
    final s = state;
    if (s is! EmployeesLoaded) return;
    emit(s.copyWith(
      roleFilter: event.role,
      clearRoleFilter: event.role == null,
      visibleEmployees: _filter(s.employees, s.query, event.role),
    ));
  }

  Future<void> _onInviteSubmitted(
    EmployeeInviteSubmitted event,
    Emitter<EmployeesState> emit,
  ) =>
      _runMutation(
        emit: emit,
        label: 'Invite employee',
        action: (gymId) =>
            _employeesRepository.createEmployee(gymId, event.request),
        onSuccess: (reloaded, created) => reloaded.copyWith(
          inviteSuccess: reloaded.inviteSuccess + 1,
          lastInvitedEmployee: created,
        ),
      );

  Future<void> _onUpdateSubmitted(
    EmployeeUpdateSubmitted event,
    Emitter<EmployeesState> emit,
  ) =>
      _runMutation(
        emit: emit,
        label: 'Update employee',
        action: (gymId) => _employeesRepository.updateEmployee(
          gymId,
          event.employeeId,
          event.data,
        ),
        onSuccess: (reloaded, _) =>
            reloaded.copyWith(updateSuccess: reloaded.updateSuccess + 1),
      );

  Future<void> _onRemoveRequested(
    EmployeeRemoveRequested event,
    Emitter<EmployeesState> emit,
  ) =>
      _runMutation(
        emit: emit,
        label: 'Remove employee',
        action: (gymId) async {
          await _employeesRepository.deleteEmployee(gymId, event.employeeId);
          return null;
        },
        onSuccess: (reloaded, _) =>
            reloaded.copyWith(removeSuccess: reloaded.removeSuccess + 1),
      );

  void _onMutationOutcomeCleared(
    EmployeesMutationOutcomeCleared event,
    Emitter<EmployeesState> emit,
  ) {
    final s = state;
    if (s is! EmployeesLoaded) return;
    emit(s.copyWith(clearMutationError: true));
  }

  /// Shared mutation flow: mark `isMutating`, run [action], reload the roster,
  /// then apply the per-action success token via [onSuccess]. A failure lands
  /// on `mutationError` (the offending dialog reads it) and never bumps a token.
  Future<void> _runMutation({
    required Emitter<EmployeesState> emit,
    required String label,
    required Future<Employee?> Function(String gymId) action,
    required EmployeesLoaded Function(EmployeesLoaded reloaded, Employee? result)
        onSuccess,
  }) async {
    final s = state;
    if (s is! EmployeesLoaded) return;
    emit(s.copyWith(isMutating: true, clearMutationError: true));
    try {
      final result = await action(s.gymId);
      final employees = await _employeesRepository.listEmployees(s.gymId);
      // Re-read state post-await so a filter/search change that arrived mid
      // flight isn't clobbered by the stale pre-await snapshot.
      final current = state;
      if (current is! EmployeesLoaded) return;
      final reloaded = current.copyWith(
        employees: employees,
        visibleEmployees:
            _filter(employees, current.query, current.roleFilter),
        isMutating: false,
        clearMutationError: true,
      );
      emit(onSuccess(reloaded, result));
    } catch (e, stackTrace) {
      log('$label failed', error: e, stackTrace: stackTrace);
      final current = state;
      if (current is! EmployeesLoaded) return;
      emit(current.copyWith(
        isMutating: false,
        mutationError: _errorMessage(e),
      ));
    }
  }

  Future<_ClassesResult> _loadClasses(String gymId) async {
    try {
      final classes = await _scheduleRepository.listClasses(gymId);
      return _ClassesResult(classes, false);
    } catch (e, stackTrace) {
      log(
        'Failed to load classes for employees (non-fatal)',
        error: e,
        stackTrace: stackTrace,
      );
      return const _ClassesResult([], true);
    }
  }

  List<Employee> _filter(
    List<Employee> all,
    String query,
    EmployeeRole? role,
  ) {
    final q = query.trim().toLowerCase();
    return all.where((e) {
      if (role != null && e.employeeType != role) return false;
      if (q.isEmpty) return true;
      return e.fullName.toLowerCase().contains(q) ||
          (e.email?.toLowerCase().contains(q) ?? false) ||
          e.employeeType.label.toLowerCase().contains(q);
    }).toList();
  }

  String _errorMessage(Object e) =>
      e is ServerException ? (e.detail ?? e.message) : e.toString();
}

/// Best-effort result of the non-fatal classes side-load.
class _ClassesResult {
  final List<GymClassResponse> classes;
  final bool failed;

  const _ClassesResult(this.classes, this.failed);
}
