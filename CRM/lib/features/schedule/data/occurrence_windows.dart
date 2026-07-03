/// Time-window predicates for one effective class occurrence — THE shared
/// start/end/check-in-window math for every surface that gates on an
/// occurrence's instant (the dashboard Live Attendance card, the occurrence
/// screen, the member check-in/reserve dialog). All predicates compare the
/// backend-computed UTC start instant (`occurredAt`) against a
/// caller-supplied `now` — never a browser-local rebuild of the gym-local
/// date/time display fields, which skew when the admin's browser timezone
/// differs from the gym's (Dart compares instants by epoch, so UTC vs local
/// `DateTime.now()` is exact).
library;

/// Check-in opens this many hours before a class starts (mirrors the backend
/// `checkin_opens_hours_before_start`) — 2h so back-to-back classes can be
/// checked in together.
const int kCheckInOpensHours = 2;

/// The occurrence's end instant (`occurredAt` + its effective duration).
DateTime occurrenceEnd(DateTime occurredAt, int durationMinutes) =>
    occurredAt.add(Duration(minutes: durationMinutes));

/// Started and not yet ended at [now].
bool occurrenceInSession(
  DateTime occurredAt,
  int durationMinutes,
  DateTime now,
) =>
    !occurredAt.isAfter(now) &&
    occurrenceEnd(occurredAt, durationMinutes).isAfter(now);

/// Check-in is open at [now]: the occurrence has started / passed, or starts
/// within the [kCheckInOpensHours] early window. The backend enforces the
/// same rule against the same instant.
bool occurrenceCheckInOpen(DateTime occurredAt, DateTime now) =>
    !occurredAt.isAfter(now.add(const Duration(hours: kCheckInOpensHours)));
