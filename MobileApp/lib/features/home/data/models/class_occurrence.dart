import 'package:json_annotation/json_annotation.dart';

part 'class_occurrence.g.dart';

/// One effective dated class occurrence on the schedule board.
///
/// Mirrors `EffectiveClassInstanceResponse` in
/// `FastApiBackend/src/classes/schema/classes_crud_schema.py` (the list read
/// `GET /api/v1/member/gyms/{gid}/members/{mid}/classes` returns
/// `{"items": [...]}`).
///
/// **Date/time fields are kept as the backend's raw ISO strings — never parsed
/// into a device-local `DateTime`.** A reservation addresses an occurrence by
/// its ORIGINAL slot `(class_id, original_date, original_time)`, so those
/// values must be echoed back VERBATIM; a timezone shift would miss the slot.
/// Display code parses copies via the `schedule_dates.dart` helpers.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class ClassOccurrence {
  final String classId;
  final String gymId;
  final String className;

  /// Effective (post-reschedule) local date, ISO `YYYY-MM-DD`.
  final String classDate;

  /// The occurrence's IDENTITY date (owning version's pre-exception slot).
  /// Echoed VERBATIM on sign-up / cancel.
  final String originalDate;

  /// The occurrence's IDENTITY time, `HH:MM:SS`. Echoed VERBATIM on sign-up.
  final String originalTime;

  /// UTC start instant, ISO — for soonest-first ordering only.
  final String occurredAt;

  /// Effective local start time, `HH:MM:SS` — what the board displays.
  final String resolvedClassTime;
  final int resolvedDurationMinutes;
  final String? resolvedInstructorId;
  final String? resolvedInstructorName;

  /// The resolved instructor's public bio, when set — shown on the class
  /// detail screen's Instructor section.
  final String? resolvedInstructorBio;

  /// The resolved instructor's photo URL, when set.
  final String? resolvedInstructorImageUrl;

  /// The class's long-form description, when set — the detail screen's
  /// Details section.
  final String? classDescription;

  /// The class image. Never null — `gym_classes.image_url` is NOT NULL.
  final String imageUrl;
  final int pointsWorth;
  final int? maxCapacity;
  final bool isCancelled;
  final bool hasInstanceException;
  final bool hasRangeException;
  final String? cancellingRangeId;
  @JsonKey(defaultValue: 0)
  final int attendanceCount;
  @JsonKey(defaultValue: 0)
  final int signupCount;

  const ClassOccurrence({
    required this.classId,
    required this.gymId,
    required this.className,
    required this.classDate,
    required this.originalDate,
    required this.originalTime,
    required this.occurredAt,
    required this.resolvedClassTime,
    required this.resolvedDurationMinutes,
    required this.imageUrl,
    required this.pointsWorth,
    required this.isCancelled,
    required this.hasInstanceException,
    required this.hasRangeException,
    this.resolvedInstructorId,
    this.resolvedInstructorName,
    this.resolvedInstructorBio,
    this.resolvedInstructorImageUrl,
    this.classDescription,
    this.maxCapacity,
    this.cancellingRangeId,
    this.attendanceCount = 0,
    this.signupCount = 0,
  });

  /// The occurrence's stable identity key — `classId|originalDate|originalTime`.
  /// This is what a reservation joins on to mark the board `booked`.
  String get slotKey => '$classId|$originalDate|$originalTime';

  factory ClassOccurrence.fromJson(Map<String, dynamic> json) =>
      _$ClassOccurrenceFromJson(json);
}
