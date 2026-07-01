import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'effective_class_instance.g.dart';

/// One effective dated class occurrence for the schedule board, from
/// `GET /api/v1/classes/instances?gym_id=&start_date=&end_date=`.
///
/// Tracks the backend `EffectiveClassInstanceResponse` field-for-field: one
/// row per occurrence after the expander applies recurrence + exceptions
/// (cancelled occurrences are included and flagged via [isCancelled]). The
/// `resolved_*` fields carry the effective value after any override.
///
/// [classDate] and [resolvedClassTime] are already in gym-local terms — render
/// as given, no timezone math. [occurredAt] is the UTC, timezone-aware start
/// instant (kept for completeness; the board renders the local date + time).
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class EffectiveClassInstance extends Equatable {
  final String classId;
  final String gymId;
  final String className;

  /// The effective (post-reschedule) local date (`YYYY-MM-DD`) — DISPLAY
  /// only. Render this, never address an occurrence by it.
  final DateTime classDate;

  /// The occurrence's IDENTITY date — the owning schedule version's
  /// pre-exception slot date (`YYYY-MM-DD`). Every occurrence-addressed call
  /// (check-in, sign-up, roster, instance exception, cancel, reschedule)
  /// passes THIS date, never [classDate].
  final DateTime originalDate;

  /// UTC, timezone-aware start instant.
  final DateTime occurredAt;

  /// Effective local start time of day as `HH:MM:SS` (render as given).
  final String resolvedClassTime;
  final int resolvedDurationMinutes;
  final String? resolvedInstructorId;
  final String? resolvedInstructorName;
  final String? imageUrl;
  final int pointsWorth;
  final int? maxCapacity;

  /// True when this occurrence is cancelled (still shown, flagged).
  final bool isCancelled;
  final bool hasInstanceException;
  final bool hasRangeException;

  /// Recorded attendance for this occurrence (0 when none; never null).
  @JsonKey(defaultValue: 0)
  final int attendanceCount;

  /// Members signed up (reserved) for this occurrence — shown for both
  /// future AND past occurrences (0 when none; never null).
  @JsonKey(defaultValue: 0)
  final int signupCount;

  const EffectiveClassInstance({
    required this.classId,
    required this.gymId,
    required this.className,
    required this.classDate,
    required this.originalDate,
    required this.occurredAt,
    required this.resolvedClassTime,
    required this.resolvedDurationMinutes,
    this.resolvedInstructorId,
    this.resolvedInstructorName,
    this.imageUrl,
    required this.pointsWorth,
    this.maxCapacity,
    required this.isCancelled,
    required this.hasInstanceException,
    required this.hasRangeException,
    this.attendanceCount = 0,
    this.signupCount = 0,
  });

  factory EffectiveClassInstance.fromJson(Map<String, dynamic> json) =>
      _$EffectiveClassInstanceFromJson(json);

  @override
  List<Object?> get props => [
        classId,
        gymId,
        className,
        classDate,
        originalDate,
        occurredAt,
        resolvedClassTime,
        resolvedDurationMinutes,
        resolvedInstructorId,
        resolvedInstructorName,
        imageUrl,
        pointsWorth,
        maxCapacity,
        isCancelled,
        hasInstanceException,
        hasRangeException,
        attendanceCount,
        signupCount,
      ];
}
