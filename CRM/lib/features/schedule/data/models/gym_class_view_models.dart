/// Pure view-models for the Schedule screen's week board.
///
/// The board renders the week as a row of day columns; each column holds that
/// day's classes stacked vertically. These types are the rendered shape — a
/// [ScheduleDayGroup] per visible day, each holding [ScheduleClassEntry] cards.
/// They are derived from the backend `EffectiveClassInstance` feed via
/// [ScheduleClassEntry.fromInstance]; nothing here talks to the network.
library;

import 'package:crm/features/schedule/data/class_time_format.dart';
import 'package:crm/features/schedule/data/models/effective_class_instance.dart';

/// One rendered class card in a day column. Built from one effective backend
/// occurrence: [classId] + [originalDate] identify this occurrence — every
/// occurrence-addressed call (check-in, sign-up, roster, cancel, reschedule)
/// uses [originalDate], never [classDate]; the rest is display data.
/// [instructorPhotoUrl] is intentionally absent — the backend serves no
/// instructor photo, so the avatar falls back to initials.
class ScheduleClassEntry {
  /// The owning `gym_classes` id — carried so a tap can open that class.
  final String classId;

  /// This occurrence's effective (post-reschedule) local date — DISPLAY
  /// only. Render this; address the occurrence by [originalDate] instead.
  final DateTime classDate;

  /// This occurrence's IDENTITY date — the owning schedule version's
  /// pre-exception slot date. Every occurrence-addressed call passes this,
  /// never [classDate].
  final DateTime originalDate;

  /// This occurrence's IDENTITY time — the owning version's pre-exception
  /// slot time (`HH:MM:SS`). With several slots per day legal, [originalDate]
  /// + [originalTime] together are the occurrence's full identity key; every
  /// occurrence-addressed call passes BOTH, never [resolvedClassTime].
  final String originalTime;
  final String name;
  final String timeLabel;
  final String? instructorName;
  final String? imageUrl;
  final int? pointsWorth;

  /// Recorded attendance for this occurrence (0 when none; never null).
  /// Only shown (as "M attended") once [occurrenceInPast] — see
  /// [signupCount] for the always-shown headcount.
  final int? attendeeCount;

  /// Members signed up (reserved) for this occurrence — shown for both
  /// future AND past occurrences (0 when none; never null). Mirrors
  /// `EffectiveClassInstance.signupCount`.
  final int signupCount;

  /// True when this occurrence has already happened — the card's headcount
  /// chip then also shows [attendeeCount] ("M attended") alongside
  /// [signupCount].
  final bool occurrenceInPast;

  /// True when this occurrence is cancelled — the card shows a badge.
  final bool isCancelled;

  /// False when the owning class is PAUSED (`gym_classes.is_active = false`).
  ///
  /// Only the schedule board ever sees a paused occurrence (it is the one
  /// read passing `includeInactive: true`); everywhere else the backend
  /// omits them, so this stays true. On the board it shows a "Paused" badge
  /// and diverts the card's tap to the class editor — check-in and sign-up
  /// would both reject the occurrence, so no check-in path may be offered.
  final bool isActive;

  /// The range exception that cancelled this occurrence — set ONLY when a
  /// RANGE exception (not an instance exception) is what cancelled it; null
  /// for an instance-cancel and for a non-cancelled occurrence. Drives the
  /// occurrence screen's "Cancelled by a range" section.
  final String? cancellingRangeId;

  /// Effective local start time of day (`HH:MM:SS`) — the raw form behind
  /// [timeLabel] (which is display-only), used to pre-fill the occurrence-edit
  /// screen's time picker.
  final String resolvedClassTime;

  /// The effective instructor's id (after any per-day or instance/range
  /// override) — pre-fills the occurrence-edit screen's instructor picker.
  /// Null when the occurrence has no instructor.
  final String? resolvedInstructorId;

  /// Effective duration in minutes — pre-fills the occurrence-edit screen's
  /// "Duration (minutes)" field and sizes the time-range labels.
  final int resolvedDurationMinutes;

  /// The occurrence's effective start INSTANT (UTC, backend-computed —
  /// `EffectiveClassInstance.occurredAt`). Any is-it-started / check-in-window
  /// gate compares THIS against `DateTime.now()` (epoch comparison, exact) —
  /// never an instant rebuilt from [classDate] + [resolvedClassTime], which
  /// are GYM-local wall-clock display fields and skew when the admin's
  /// browser timezone differs from the gym's.
  final DateTime occurredAt;

  /// Effective max capacity (null = uncapped) — pre-fills the occurrence-edit
  /// screen's capacity field. The backend `/classes/instances` read resolves a
  /// per-day `new_max_capacity` instance override here (falling back to the
  /// class default), so the prefill matches what the check-in capacity gate
  /// enforces — a re-save no longer silently reverts a saved capacity override.
  final int? maxCapacity;

  const ScheduleClassEntry({
    required this.classId,
    required this.classDate,
    required this.originalDate,
    required this.originalTime,
    required this.name,
    required this.timeLabel,
    required this.resolvedClassTime,
    required this.resolvedDurationMinutes,
    required this.occurredAt,
    this.resolvedInstructorId,
    this.instructorName,
    this.imageUrl,
    this.pointsWorth,
    this.attendeeCount,
    this.signupCount = 0,
    this.occurrenceInPast = false,
    this.isCancelled = false,
    this.isActive = true,
    this.cancellingRangeId,
    this.maxCapacity,
  });

  /// The ONE mapping from a backend occurrence to its rendered entry —
  /// shared by the schedule board and the dashboard's Live Attendance card
  /// so a pushed occurrence screen receives identical data from either
  /// surface.
  factory ScheduleClassEntry.fromInstance(EffectiveClassInstance i) =>
      ScheduleClassEntry(
        classId: i.classId,
        classDate: i.classDate,
        originalDate: i.originalDate,
        originalTime: i.originalTime,
        name: i.className,
        timeLabel: classTimeRangeLabel(
          i.resolvedClassTime,
          i.resolvedDurationMinutes,
        ),
        instructorName: i.resolvedInstructorName,
        imageUrl: i.imageUrl,
        pointsWorth: i.pointsWorth,
        attendeeCount: i.attendanceCount,
        signupCount: i.signupCount,
        occurredAt: i.occurredAt,
        occurrenceInPast: i.occurredAt.isBefore(DateTime.now()),
        isCancelled: i.isCancelled,
        isActive: i.isActive,
        cancellingRangeId: i.cancellingRangeId,
        resolvedClassTime: i.resolvedClassTime,
        resolvedInstructorId: i.resolvedInstructorId,
        resolvedDurationMinutes: i.resolvedDurationMinutes,
        maxCapacity: i.maxCapacity,
      );
}

/// One day column on the board: a labelled header above that day's cards.
class ScheduleDayGroup {
  final String dayLabel;
  final List<ScheduleClassEntry> classes;

  /// Marks the current day so its column header is highlighted.
  final bool isToday;

  const ScheduleDayGroup({
    required this.dayLabel,
    required this.classes,
    this.isToday = false,
  });
}
