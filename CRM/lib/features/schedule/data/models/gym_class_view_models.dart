/// Pure view-models for the Schedule screen's week board.
///
/// The board renders the week as a row of day columns; each column holds that
/// day's classes stacked vertically. These types are the rendered shape — a
/// [ScheduleDayGroup] per visible day, each holding [ScheduleClassEntry] cards.
/// They are derived from the backend `EffectiveClassInstance` feed by the board
/// mapper (`schedule_screen.dart`); nothing here talks to the network.
library;

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

  /// Effective duration in minutes. The occurrence-edit screen doesn't expose
  /// a duration field, so this is carried through unedited on an override save
  /// — the instance-exception upsert replaces every override field at once, so
  /// omitting it would blank out a previously-set duration override.
  final int resolvedDurationMinutes;

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
    required this.name,
    required this.timeLabel,
    required this.resolvedClassTime,
    required this.resolvedDurationMinutes,
    this.resolvedInstructorId,
    this.instructorName,
    this.imageUrl,
    this.pointsWorth,
    this.attendeeCount,
    this.signupCount = 0,
    this.occurrenceInPast = false,
    this.isCancelled = false,
    this.cancellingRangeId,
    this.maxCapacity,
  });
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
