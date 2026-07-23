// Pure decision logic for the post-class celebration — no I/O, no widgets,
// fully unit-testable without shared_preferences.

/// What the per-member watermark says to do with the newest attended class.
enum CelebrationDecision {
  /// No watermark yet — SEED it silently to the newest attendance and fire
  /// NOTHING, so a first run / reinstall / member switch never replays
  /// historical attendance.
  seedSilently,

  /// The newest attendance is STRICTLY newer than the watermark — celebrate it
  /// once, then advance the watermark to it.
  fire,

  /// Already seen (equal or older) — do nothing.
  skip,
}

/// The watermark rule: null seeds silently, a strictly-newer attendance fires,
/// an equal/older one is skipped.
CelebrationDecision decideCelebration({
  required DateTime? lastSeen,
  required DateTime newestAttended,
}) {
  if (lastSeen == null) return CelebrationDecision.seedSilently;
  if (newestAttended.isAfter(lastSeen)) return CelebrationDecision.fire;
  return CelebrationDecision.skip;
}

/// Sunday-first strip index (0 = Sun … 6 = Sat) for a date. Dart's `weekday`
/// is Mon = 1 … Sun = 7; `% 7` folds Sunday (7) back to 0.
int sundayStripIndex(DateTime date) => date.weekday % 7;

/// The Sunday-first weekday indices (0..6) the member trained during the week
/// that CONTAINS [anchorDate], derived from [attendedDates] (the class-history
/// head's attended-row `original_date`s). The anchor's own day is always
/// included — it's the class just attended — so an empty [attendedDates]
/// yields a single-day strip. Dates are compared date-only in UTC so the week
/// window is DST-proof.
List<int> completedWeekdayIndices({
  required DateTime anchorDate,
  required Iterable<DateTime> attendedDates,
}) {
  final anchor = _dateOnlyUtc(anchorDate);
  final weekStart = anchor.subtract(Duration(days: sundayStripIndex(anchor)));
  final weekEnd = weekStart.add(const Duration(days: 6));
  final indices = <int>{sundayStripIndex(anchor)};
  for (final raw in attendedDates) {
    final day = _dateOnlyUtc(raw);
    if (day.isBefore(weekStart) || day.isAfter(weekEnd)) continue;
    indices.add(sundayStripIndex(day));
  }
  return indices.toList()..sort();
}

DateTime _dateOnlyUtc(DateTime d) => DateTime.utc(d.year, d.month, d.day);
