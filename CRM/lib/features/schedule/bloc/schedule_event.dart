import 'package:equatable/equatable.dart';

import 'package:crm/features/schedule/data/models/gym_class_create_request.dart';
import 'package:crm/features/schedule/data/models/gym_class_update_request.dart';

sealed class ScheduleEvent extends Equatable {
  const ScheduleEvent();

  @override
  List<Object?> get props => [];
}

/// Load the board for [gymId], for the week starting [weekStart] (a local
/// Sunday at midnight). Dispatched once when the screen mounts.
class ScheduleInitRequested extends ScheduleEvent {
  final String gymId;
  final DateTime weekStart;

  /// False when the host never renders the week board — the dashboard's
  /// Live Attendance card hosts this bloc only for its mutation/check-in
  /// channels and the class catalog, so it skips the instances fetch on the
  /// dashboard hot path (mutation reloads still refetch the week).
  final bool loadBoard;

  const ScheduleInitRequested({
    required this.gymId,
    required this.weekStart,
    this.loadBoard = true,
  });

  @override
  List<Object?> get props => [gymId, weekStart, loadBoard];
}

/// Move the board to the week starting [weekStart] (prev/next navigation).
/// Reuses the gym id captured at init.
class ScheduleWeekChanged extends ScheduleEvent {
  final DateTime weekStart;

  const ScheduleWeekChanged(this.weekStart);

  @override
  List<Object?> get props => [weekStart];
}

/// Create a class from the form, then reload the board.
class ScheduleClassCreated extends ScheduleEvent {
  final GymClassCreateRequest request;

  const ScheduleClassCreated(this.request);
}

/// Update class [classId] with [request] (split `identity` / `schedule`
/// halves — see `GymClassUpdateRequest`), then reload the board.
class ScheduleClassUpdated extends ScheduleEvent {
  final String classId;
  final GymClassUpdateRequest request;

  const ScheduleClassUpdated({required this.classId, required this.request});
}

/// Soft-delete class [classId], then reload the board.
class ScheduleClassDeleted extends ScheduleEvent {
  final String classId;

  const ScheduleClassDeleted(this.classId);

  @override
  List<Object?> get props => [classId];
}

/// Cancel the single occurrence of [classId] on [originalDate] +
/// [originalTime] (the occurrence's IDENTITY slot — a one-slot exception;
/// several slots per day are legal, so a same-day sibling is untouched), then
/// reload the board so the cancelled day shows its badge.
class ScheduleInstanceCancelled extends ScheduleEvent {
  final String classId;
  final DateTime originalDate;
  final String originalTime;

  const ScheduleInstanceCancelled({
    required this.classId,
    required this.originalDate,
    required this.originalTime,
  });

  @override
  List<Object?> get props => [classId, originalDate, originalTime];
}

/// Staff batch check-in ("Update attendees"): check [memberIds] into the
/// occurrence of [classId] on [occurrenceDate] + [occurrenceTime] (the
/// occurrence's IDENTITY key, never its display date/time), then reload the
/// board so the attendance count updates. The CRM is the staff surface
/// (`is_member: false`): a clean member is recorded, and one the gate warns
/// on comes back as `needs_confirmation` (nothing written) unless
/// [ignoreWarnings] is set — the results dialog resubmits just the
/// `needs_confirmation` subset with it true ("Check in anyway"), merging the
/// confirmation response back into the full breakdown. The outcome lands on
/// `batchCheckInResult` (the per-member 207 breakdown, each row carrying any
/// non-blocking warnings) or `checkInError`.
class ScheduleBatchCheckInRequested extends ScheduleEvent {
  final String classId;
  final DateTime occurrenceDate;
  final String occurrenceTime;
  final List<String> memberIds;
  final bool ignoreWarnings;

  const ScheduleBatchCheckInRequested({
    required this.classId,
    required this.occurrenceDate,
    required this.occurrenceTime,
    required this.memberIds,
    this.ignoreWarnings = false,
  });

  @override
  List<Object?> get props =>
      [classId, occurrenceDate, occurrenceTime, memberIds, ignoreWarnings];
}

/// Clears the batch check-in outcome (result + error) when the check-in dialog
/// opens or closes, so a later run opens clean.
class ScheduleBatchCheckInCleared extends ScheduleEvent {
  const ScheduleBatchCheckInCleared();
}

/// "Reserve members": reserve [memberIds] a spot on the occurrence of
/// [classId] on [occurrenceDate] + [occurrenceTime] (the occurrence's
/// IDENTITY key), then reload the board so the board's reserved count
/// updates. There is no batch sign-up endpoint — the repository loops
/// `POST /api/v1/signup` once per member; one member's failure (e.g. "Class
/// is full", a transport error) never sinks the rest. The per-member
/// breakdown lands on `signupResult`.
class ScheduleSignUpRequested extends ScheduleEvent {
  final String classId;
  final DateTime occurrenceDate;
  final String occurrenceTime;
  final List<String> memberIds;

  const ScheduleSignUpRequested({
    required this.classId,
    required this.occurrenceDate,
    required this.occurrenceTime,
    required this.memberIds,
  });

  @override
  List<Object?> get props =>
      [classId, occurrenceDate, occurrenceTime, memberIds];
}

/// Clears the sign-up outcome when the "Reserve members" dialog opens or
/// closes, so a later run opens clean.
class ScheduleSignUpCleared extends ScheduleEvent {
  const ScheduleSignUpCleared();
}

/// Override the single occurrence of [classId] on [originalDate] +
/// [originalTime] (the occurrence's IDENTITY slot — a one-slot exception; a
/// same-day sibling slot is untouched): set its effective instructor / start
/// time / max capacity, then reload the board. Mirrors
/// [ScheduleInstanceCancelled] but with `is_cancelled: false` and the
/// override fields populated. [newClassTime] is `HH:MM:SS`;
/// [newDurationMinutes] is carried through unedited (the occurrence-edit
/// screen has no duration field) so the upsert doesn't blank a
/// previously-set duration override. [newDate] (`YYYY-MM-DD`) is a
/// **reschedule** — moving this occurrence to another day, any date (past,
/// today, or future) — and is only set when the user actually picked a
/// different date; the backend rejects only a collision with an existing
/// non-cancelled occurrence at the exact target instant. Scope:
/// [originalDate] / [originalTime] are assumed to be the occurrence's
/// original (not-yet-moved) slot — rescheduling an already-rescheduled
/// occurrence a second time is out of scope.
class ScheduleInstanceOverridden extends ScheduleEvent {
  final String classId;
  final DateTime originalDate;
  final String originalTime;
  final String newClassTime;
  final int newDurationMinutes;
  final int? newMaxCapacity;
  final String? newInstructorId;
  final DateTime? newDate;

  const ScheduleInstanceOverridden({
    required this.classId,
    required this.originalDate,
    required this.originalTime,
    required this.newClassTime,
    required this.newDurationMinutes,
    this.newMaxCapacity,
    this.newInstructorId,
    this.newDate,
  });

  @override
  List<Object?> get props => [
        classId,
        originalDate,
        originalTime,
        newClassTime,
        newDurationMinutes,
        newMaxCapacity,
        newInstructorId,
        newDate,
      ];
}

/// Cancel every occurrence of [classId] in the inclusive range `[start, end]`
/// (a range exception), then reload the board.
class ScheduleRangeCancelled extends ScheduleEvent {
  final String classId;
  final DateTime start;
  final DateTime end;

  const ScheduleRangeCancelled({
    required this.classId,
    required this.start,
    required this.end,
  });

  @override
  List<Object?> get props => [classId, start, end];
}

/// Move range exception [exceptionId] (of [classId]) to `[start, end]`, then
/// reload the board. For a CANCEL range the backend atomically re-runs the
/// create path's teardown over the NEW coverage — newly covered upcoming
/// dates lose their reservations and early check-ins (points reversed);
/// dates that fall out of coverage are never restored.
class ScheduleRangeExceptionUpdated extends ScheduleEvent {
  final String classId;
  final String exceptionId;
  final DateTime start;
  final DateTime end;

  const ScheduleRangeExceptionUpdated({
    required this.classId,
    required this.exceptionId,
    required this.start,
    required this.end,
  });

  @override
  List<Object?> get props => [classId, exceptionId, start, end];
}

/// Remove range exception [exceptionId] (of [classId]) outright, then reload
/// the board. Covered dates revive; anything already torn down while it was
/// active is not restored.
class ScheduleRangeExceptionDeleted extends ScheduleEvent {
  final String classId;
  final String exceptionId;

  const ScheduleRangeExceptionDeleted({
    required this.classId,
    required this.exceptionId,
  });

  @override
  List<Object?> get props => [classId, exceptionId];
}
