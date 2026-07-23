import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:mobile_app/core/errors/exceptions.dart';
import 'package:mobile_app/core/state/selected_member.dart';
import 'package:mobile_app/features/home/bloc/home_event.dart';
import 'package:mobile_app/features/home/bloc/home_state.dart';
import 'package:mobile_app/features/home/data/models/class_history.dart';
import 'package:mobile_app/features/home/data/models/class_occurrence.dart';
import 'package:mobile_app/features/home/data/models/upcoming_session.dart';
import 'package:mobile_app/features/home/data/repositories/member_class_history_repository.dart';
import 'package:mobile_app/features/home/data/repositories/member_classes_repository.dart';
import 'package:mobile_app/features/home/data/schedule_dates.dart';

/// Drives the home schedule: it loads the board over a date window AND the
/// member's open reservations, then JOINS them — an occurrence is `booked`
/// when an open reservation matches its slot key. The board is the primary
/// content (a fetch failure is a retry-able error); a class-history failure
/// only drops the booked flags + upcoming card (degraded, not fatal).
class HomeBloc extends Bloc<HomeEvent, HomeState> {
  final MemberClassesRepository _classesRepository;
  final MemberClassHistoryRepository _historyRepository;

  HomeBloc({
    required MemberClassesRepository classesRepository,
    required MemberClassHistoryRepository historyRepository,
  })  : _classesRepository = classesRepository,
        _historyRepository = historyRepository,
        super(const HomeState()) {
    on<HomeLoadRequested>(_onLoadRequested);
    on<HomeRefreshRequested>(_onRefreshRequested);
    on<HomeExtendRequested>(_onExtendRequested);
  }

  String? get _memberId => selectedMember.memberId;
  String? get _gymId => selectedMember.gymId;

  Future<void> _onLoadRequested(
    HomeLoadRequested event,
    Emitter<HomeState> emit,
  ) async {
    emit(state.copyWith(status: HomeStatus.loading, clearError: true));
    await _fetchWindow(state.windowDays, emit);
  }

  Future<void> _onRefreshRequested(
    HomeRefreshRequested event,
    Emitter<HomeState> emit,
  ) async {
    if (_gymId == null || _memberId == null) return;
    emit(state.copyWith(isRefreshing: true, clearError: true));
    await _fetchWindow(state.windowDays, emit, keepContent: true);
    emit(state.copyWith(isRefreshing: false));
  }

  Future<void> _onExtendRequested(
    HomeExtendRequested event,
    Emitter<HomeState> emit,
  ) async {
    if (state.isExtending || !state.canExtend) return;
    if (state.status != HomeStatus.loaded) return;
    final next =
        (state.windowDays + HomeState.extendStepDays).clamp(0, HomeState.maxWindowDays);
    emit(state.copyWith(isExtending: true));
    await _fetchWindow(next, emit, keepContent: true, windowDays: next);
    emit(state.copyWith(isExtending: false));
  }

  /// Fetch the board + reservations for a [days]-wide window and emit the
  /// joined result. When [keepContent] is true a failure keeps whatever is on
  /// screen (refresh / extend) instead of flipping to the error state.
  Future<void> _fetchWindow(
    int days,
    Emitter<HomeState> emit, {
    bool keepContent = false,
    int? windowDays,
  }) async {
    final gymId = _gymId;
    final memberId = _memberId;
    if (gymId == null || memberId == null) return;

    final startDate = isoDate(todayLocal());
    final endDate = isoDate(dateForOffset(days - 1));

    final List<ClassOccurrence> board;
    try {
      board = await _classesRepository.getBoard(
        gymId: gymId,
        memberId: memberId,
        startDate: startDate,
        endDate: endDate,
      );
    } catch (e, st) {
      log('HomeBloc: board fetch failed', error: e, stackTrace: st);
      if (!keepContent) {
        emit(state.copyWith(
          status: HomeStatus.error,
          errorMessage: _userMessage(e),
        ));
      }
      return;
    }

    // Reservations are best-effort: a failure drops booked flags + the
    // upcoming card but never hides the schedule.
    MemberClassHistory? history;
    try {
      history = await _historyRepository.getHistory(
        gymId: gymId,
        memberId: memberId,
      );
    } catch (e, st) {
      log('HomeBloc: history fetch failed (degrading)', error: e, stackTrace: st);
    }

    final sorted = [...board]..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    final byKey = {for (final o in sorted) o.slotKey: o};
    final reservations = history?.upcoming ?? const <MemberClassHistoryRow>[];
    final bookedKeys = {for (final r in reservations) r.slotKey};
    final upcoming = [for (final r in reservations) _toUpcoming(r, byKey)];

    emit(state.copyWith(
      status: HomeStatus.loaded,
      occurrences: sorted,
      bookedKeys: bookedKeys,
      upcoming: upcoming,
      windowDays: windowDays,
      clearError: true,
    ));
  }

  UpcomingSession _toUpcoming(
    MemberClassHistoryRow row,
    Map<String, ClassOccurrence> byKey,
  ) {
    final occ = byKey[row.slotKey];
    final dateStr = occ?.classDate ?? row.originalDate;
    final date = parseIsoDate(dateStr);
    final dayLabel =
        date != null ? dayLabelForOffset(dayOffsetForDate(date)) : dateStr;
    final time = occ?.resolvedClassTime ?? row.originalTime;
    return UpcomingSession(
      dayLabel: dayLabel,
      timeLabel: formatClockTime(time),
      className: occ?.className ?? row.className,
      durationMinutes: occ?.resolvedDurationMinutes ?? row.durationMinutes,
      mentor: occ?.resolvedInstructorName,
      occurrence: occ,
    );
  }

  String _userMessage(Object e) {
    if (e is ServerException) return e.detail ?? e.message;
    if (e is NetworkException) return e.message;
    return 'Something went wrong. Please try again.';
  }
}
