import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import 'package:crm/features/check_in/data/models/batch_check_in_request.dart';
import 'package:crm/features/check_in/data/models/batch_check_in_response.dart';
import 'package:crm/features/schedule/bloc/schedule_event.dart';
import 'package:crm/features/schedule/bloc/schedule_state.dart';
import 'package:crm/features/schedule/data/models/gym_class_response.dart';
import 'package:crm/features/schedule/data/repositories/schedule_repository.dart';

/// Drives the Schedule week board: loads the effective class occurrences for
/// the visible week (plus the gym's class catalog), re-loads on prev/next week
/// navigation, and runs the class create / edit / soft-delete mutations,
/// reloading the board on success.
class ScheduleBloc extends Bloc<ScheduleEvent, ScheduleState> {
  /// Backend `occurrence_date` body fields are bare `YYYY-MM-DD` (gym-local).
  static final DateFormat _dateParam = DateFormat('yyyy-MM-dd');

  final ScheduleRepository _repository;

  /// Captured from [ScheduleInitRequested] so week changes + mutation reloads
  /// reuse it.
  String _gymId = '';

  /// The currently-loaded week (a Sunday); mutation reloads re-fetch it.
  DateTime _weekStart = DateTime(2000);

  ScheduleBloc({required ScheduleRepository repository})
      : _repository = repository,
        super(const ScheduleInitial()) {
    on<ScheduleInitRequested>(_onInitRequested);
    on<ScheduleWeekChanged>(_onWeekChanged);
    on<ScheduleClassCreated>(_onClassCreated);
    on<ScheduleClassUpdated>(_onClassUpdated);
    on<ScheduleClassDeleted>(_onClassDeleted);
    on<ScheduleInstanceCancelled>(_onInstanceCancelled);
    on<ScheduleRangeCancelled>(_onRangeCancelled);
    on<ScheduleBatchCheckInRequested>(_onBatchCheckIn);
    on<ScheduleBatchCheckInCleared>(_onBatchCheckInCleared);
  }

  Future<void> _onInitRequested(
    ScheduleInitRequested event,
    Emitter<ScheduleState> emit,
  ) async {
    _gymId = event.gymId;
    await _load(emit, event.weekStart, knownClasses: null);
  }

  Future<void> _onWeekChanged(
    ScheduleWeekChanged event,
    Emitter<ScheduleState> emit,
  ) async {
    // The class catalog is week-independent; carry it across a week change so
    // only the instances re-fetch.
    final current = state;
    final known = current is ScheduleLoaded ? current.classes : null;
    await _load(emit, event.weekStart, knownClasses: known);
  }

  Future<void> _onClassCreated(
    ScheduleClassCreated event,
    Emitter<ScheduleState> emit,
  ) =>
      _mutateAndReload(emit, () => _repository.createClass(event.request));

  Future<void> _onClassUpdated(
    ScheduleClassUpdated event,
    Emitter<ScheduleState> emit,
  ) =>
      _mutateAndReload(
        emit,
        () => _repository.updateClass(event.classId, event.data),
      );

  Future<void> _onClassDeleted(
    ScheduleClassDeleted event,
    Emitter<ScheduleState> emit,
  ) =>
      _mutateAndReload(emit, () => _repository.deleteClass(event.classId));

  Future<void> _onInstanceCancelled(
    ScheduleInstanceCancelled event,
    Emitter<ScheduleState> emit,
  ) =>
      _mutateAndReload(
        emit,
        () => _repository.cancelInstance(event.classId, event.date),
      );

  Future<void> _onRangeCancelled(
    ScheduleRangeCancelled event,
    Emitter<ScheduleState> emit,
  ) =>
      _mutateAndReload(
        emit,
        () => _repository.cancelRange(event.classId, event.start, event.end),
      );

  /// Staff batch check-in. A DEDICATED channel (`isCheckingIn` /
  /// `batchCheckInResult` / `checkInError` on [ScheduleLoaded]) — NOT the
  /// `isMutating` class-CRUD path — so the check-in dialog owns its own
  /// processing → results step without colliding with the board's mutation
  /// overlay (mirrors the member-detail charge-card channel). The endpoint
  /// returns 207 Multi-Status (a 2xx; Dio does not throw), so the per-member
  /// breakdown arrives on the success path. On success the visible week is
  /// reloaded so the attendance count updates behind the still-open results.
  Future<void> _onBatchCheckIn(
    ScheduleBatchCheckInRequested event,
    Emitter<ScheduleState> emit,
  ) async {
    final current = state;
    if (current is! ScheduleLoaded) return;
    emit(current.copyWith(isCheckingIn: true, clearCheckIn: true));

    final BatchCheckInResponse result;
    try {
      result = await _repository.batchCheckIn(
        BatchCheckInRequest(
          gymId: _gymId,
          classId: event.classId,
          occurrenceDate: _dateParam.format(event.occurrenceDate),
          memberIds: event.memberIds,
        ),
      );
    } catch (e, stackTrace) {
      log('Batch check-in failed', error: e, stackTrace: stackTrace);
      final latest = state;
      if (latest is! ScheduleLoaded) return;
      emit(latest.copyWith(
        isCheckingIn: false,
        checkInError: e.toString(),
      ));
      return;
    }

    // The 207 came back — members were processed. Commit the result NOW so a
    // failure of the best-effort board reload below can't make a real check-in
    // look failed. Mirrors the charge-card "commit before refresh" pattern.
    final committed = state;
    if (committed is! ScheduleLoaded) return;
    emit(committed.copyWith(
      isCheckingIn: false,
      batchCheckInResult: result,
    ));

    // Best-effort: reload the visible week so the board's attendance count
    // updates behind the still-open results step. Keep the committed result.
    try {
      final weekEnd = _weekStart.add(const Duration(days: 6));
      final instances = await _repository.listEffectiveInstances(
        _gymId,
        _weekStart,
        weekEnd,
      );
      final classes = await _repository.listClasses(_gymId);
      final latest = state;
      if (latest is! ScheduleLoaded) return;
      emit(ScheduleLoaded(
        weekStart: _weekStart,
        instances: instances,
        classes: classes,
        actionSuccessCount: latest.actionSuccessCount,
        batchCheckInResult: latest.batchCheckInResult,
      ));
    } catch (e, stackTrace) {
      log(
        'Check-in succeeded but board reload failed (non-fatal)',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  void _onBatchCheckInCleared(
    ScheduleBatchCheckInCleared event,
    Emitter<ScheduleState> emit,
  ) {
    final current = state;
    if (current is! ScheduleLoaded) return;
    emit(current.copyWith(clearCheckIn: true));
  }

  /// Fetch the week's instances (and the class catalog when not already known)
  /// for [weekStart] (a Sunday); the week spans the following six days.
  Future<void> _load(
    Emitter<ScheduleState> emit,
    DateTime weekStart, {
    required List<GymClassResponse>? knownClasses,
  }) async {
    emit(const ScheduleLoading());
    _weekStart = weekStart;
    final weekEnd = weekStart.add(const Duration(days: 6));
    try {
      final instances = await _repository.listEffectiveInstances(
        _gymId,
        weekStart,
        weekEnd,
      );
      final classes =
          knownClasses ?? await _repository.listClasses(_gymId);
      emit(ScheduleLoaded(
        weekStart: weekStart,
        instances: instances,
        classes: classes,
      ));
    } catch (e, stackTrace) {
      log('Failed to load schedule', error: e, stackTrace: stackTrace);
      emit(ScheduleError(e.toString()));
    }
  }

  /// Runs [action] (a class write), then reloads the current week's board.
  /// On success bumps `actionSuccessCount`; on failure surfaces `actionError`
  /// without dropping the board (or as [ScheduleError] if nothing is loaded).
  /// Mirrors `PlansBloc._mutateAndReload`.
  Future<void> _mutateAndReload(
    Emitter<ScheduleState> emit,
    Future<void> Function() action,
  ) async {
    final current = state;
    final priorSuccess =
        current is ScheduleLoaded ? current.actionSuccessCount : 0;
    if (current is ScheduleLoaded) {
      emit(current.copyWith(isMutating: true));
    }
    try {
      await action();
      final weekEnd = _weekStart.add(const Duration(days: 6));
      final instances = await _repository.listEffectiveInstances(
        _gymId,
        _weekStart,
        weekEnd,
      );
      final classes = await _repository.listClasses(_gymId);
      emit(ScheduleLoaded(
        weekStart: _weekStart,
        instances: instances,
        classes: classes,
        actionSuccessCount: priorSuccess + 1,
      ));
    } catch (e, stackTrace) {
      log('Class mutation failed', error: e, stackTrace: stackTrace);
      if (current is ScheduleLoaded) {
        emit(current.copyWith(isMutating: false, actionError: e.toString()));
      } else {
        emit(ScheduleError(e.toString()));
      }
    }
  }
}
