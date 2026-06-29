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

  const ScheduleInitRequested({required this.gymId, required this.weekStart});

  @override
  List<Object?> get props => [gymId, weekStart];
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

/// Update class [classId] with [data], then reload the board.
class ScheduleClassUpdated extends ScheduleEvent {
  final String classId;
  final GymClassUpdateData data;

  const ScheduleClassUpdated({required this.classId, required this.data});
}

/// Soft-delete class [classId], then reload the board.
class ScheduleClassDeleted extends ScheduleEvent {
  final String classId;

  const ScheduleClassDeleted(this.classId);

  @override
  List<Object?> get props => [classId];
}

/// Cancel the single occurrence of [classId] on [date] (a one-day exception),
/// then reload the board so the cancelled day shows its badge.
class ScheduleInstanceCancelled extends ScheduleEvent {
  final String classId;
  final DateTime date;

  const ScheduleInstanceCancelled({required this.classId, required this.date});

  @override
  List<Object?> get props => [classId, date];
}

/// Staff batch check-in ("Update attendees"): check [memberIds] into the
/// occurrence of [classId] on [occurrenceDate], then reload the board so the
/// attendance count updates. The outcome lands on `batchCheckInResult` (the
/// per-member 207 breakdown) or `checkInError`. [allowOverride] forces every
/// member past the eligibility / capacity gates (retroactive / over-capacity /
/// depleted).
class ScheduleBatchCheckInRequested extends ScheduleEvent {
  final String classId;
  final DateTime occurrenceDate;
  final List<String> memberIds;
  final bool allowOverride;

  const ScheduleBatchCheckInRequested({
    required this.classId,
    required this.occurrenceDate,
    required this.memberIds,
    this.allowOverride = false,
  });

  @override
  List<Object?> get props =>
      [classId, occurrenceDate, memberIds, allowOverride];
}

/// Clears the batch check-in outcome (result + error) when the check-in dialog
/// opens or closes, so a later run opens clean.
class ScheduleBatchCheckInCleared extends ScheduleEvent {
  const ScheduleBatchCheckInCleared();
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
