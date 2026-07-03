import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/features/home/bloc/live_attendance_event.dart';
import 'package:crm/features/home/bloc/live_attendance_state.dart';
import 'package:crm/features/home/data/live_attendance_section.dart';
import 'package:crm/features/schedule/data/models/effective_class_instance.dart';
import 'package:crm/features/schedule/data/repositories/schedule_repository.dart';

/// How far BACK the instances window reaches — one day, so a class that
/// started before local midnight and is still running isn't missed.
const int _kLookbackDays = 1;

/// How far AHEAD the window reaches when hunting the NEXT occurrence for the
/// nothing-live preview (mirrors the Upcoming Classes card's lookahead).
const int _kLookaheadDays = 14;

/// BLoC for the dashboard's Live Attendance card. Two reads per load, both
/// against the real backend via [ScheduleRepository]:
///
/// 1. `GET /api/v1/classes/instances` over `[today − 1d, today + 14d]`,
///    split by each occurrence's backend-computed UTC start instant
///    (`occurredAt`, never a browser-local rebuild of the gym-local
///    date/time) against `DateTime.now()`: **in session** = started and not
///    yet ended (`+ resolvedDurationMinutes`). Nothing live → fall forward
///    to the soonest upcoming occurrence as a preview (every occurrence
///    sharing that exact start instant, so simultaneous classes both show).
/// 2. `GET /api/v1/checkin/attendees` per shown occurrence — the combined
///    signed-up ∪ attended roster that becomes the card's rows.
///
/// Self-contained like the Overdue Payments / Upcoming Classes blocs. The
/// card's 60s poll dispatches [LiveAttendanceRefreshRequested]; a failed
/// refresh keeps the last data (and a later successful tick self-heals an
/// error state).
class LiveAttendanceBloc
    extends Bloc<LiveAttendanceEvent, LiveAttendanceState> {
  final ScheduleRepository _repository;

  /// Captured from [LiveAttendanceLoadRequested] so refresh ticks reuse it.
  String _gymId = '';

  LiveAttendanceBloc({required ScheduleRepository repository})
      : _repository = repository,
        super(const LiveAttendanceInitial()) {
    on<LiveAttendanceLoadRequested>(_onLoadRequested);
    on<LiveAttendanceRefreshRequested>(_onRefreshRequested);
  }

  Future<void> _onLoadRequested(
    LiveAttendanceLoadRequested event,
    Emitter<LiveAttendanceState> emit,
  ) async {
    _gymId = event.gymId;
    emit(const LiveAttendanceLoading());
    try {
      emit(await _fetch());
    } catch (e, stackTrace) {
      log('Failed to load live attendance', error: e, stackTrace: stackTrace);
      emit(LiveAttendanceError(e.toString(), gymId: event.gymId));
    }
  }

  Future<void> _onRefreshRequested(
    LiveAttendanceRefreshRequested event,
    Emitter<LiveAttendanceState> emit,
  ) async {
    if (_gymId.isEmpty) return;
    try {
      emit(await _fetch());
    } catch (e, stackTrace) {
      // Silent: keep whatever the card is showing; the next tick retries.
      log(
        'Live attendance refresh failed (kept last data)',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<LiveAttendanceLoaded> _fetch() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final instances = await _repository.listEffectiveInstances(
      _gymId,
      today.subtract(const Duration(days: _kLookbackDays)),
      today.add(const Duration(days: _kLookaheadDays)),
    );
    final active = instances.where((i) => !i.isCancelled).toList();

    var shown = _inSession(active, now);
    final isNextPreview = shown.isEmpty;
    if (isNextPreview) shown = _nextUpcoming(active, now);

    final sections = <LiveAttendanceSection>[];
    for (final i in shown) {
      final roster = await _repository.listAttendees(
        _gymId,
        i.classId,
        i.originalDate,
        i.originalTime,
      );
      sections.add(
        LiveAttendanceSection(instance: i, attendees: roster.attendees),
      );
    }
    return LiveAttendanceLoaded(
      sections: sections,
      isNextPreview: isNextPreview,
    );
  }

  /// Occurrences currently running: started ([EffectiveClassInstance]'s UTC
  /// `occurredAt` at or before [now]) and not yet ended (start + duration
  /// after [now]). Soonest-started first.
  List<EffectiveClassInstance> _inSession(
    List<EffectiveClassInstance> active,
    DateTime now,
  ) {
    return active.where((i) {
      final end =
          i.occurredAt.add(Duration(minutes: i.resolvedDurationMinutes));
      return !i.occurredAt.isAfter(now) && end.isAfter(now);
    }).toList()
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
  }

  /// The soonest not-yet-started occurrence(s) — every occurrence sharing
  /// the earliest upcoming start instant, so two classes starting together
  /// both preview. Empty when the gym has nothing scheduled ahead.
  List<EffectiveClassInstance> _nextUpcoming(
    List<EffectiveClassInstance> active,
    DateTime now,
  ) {
    final upcoming = active.where((i) => i.occurredAt.isAfter(now)).toList()
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    if (upcoming.isEmpty) return const [];
    final soonest = upcoming.first.occurredAt;
    return upcoming
        .where((i) => i.occurredAt.isAtSameMomentAs(soonest))
        .toList();
  }
}
