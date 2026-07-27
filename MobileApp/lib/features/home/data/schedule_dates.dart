// Pure date/time helpers for the schedule board.
//
// The date tabs and day groups are keyed by an integer day-offset from today
// (0 = today, 1 = tomorrow, …). These helpers turn an offset — or a backend
// ISO date/time string — into the labels the board renders. They hold no
// state and read the device clock only through `todayLocal`.

const _weekdayAbbr = <String>[
  '',
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

const _weekdayFull = <String>[
  '',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// Local midnight today — the anchor every day-offset is measured from.
DateTime todayLocal() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

/// The local date [dayOffset] days after today.
DateTime dateForOffset(int dayOffset) =>
    todayLocal().add(Duration(days: dayOffset));

String _twoDigit(int n) => n.toString().padLeft(2, '0');

/// ISO `YYYY-MM-DD` for a local date — the wire format the board window uses.
String isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${_twoDigit(date.month)}-${_twoDigit(date.day)}';

/// Whole days between today and [date] (a gym-local ISO date). Negative for
/// past days. Used to bucket a board occurrence into its day group / tab.
int dayOffsetForDate(DateTime date) {
  final d = DateTime(date.year, date.month, date.day);
  return d.difference(todayLocal()).inDays;
}

/// Short tab label: `Today`, `Tomorrow`, else `Mon 28`.
String dayLabelForOffset(int dayOffset) {
  if (dayOffset == 0) return 'Today';
  if (dayOffset == 1) return 'Tomorrow';
  final date = dateForOffset(dayOffset);
  return '${_weekdayAbbr[date.weekday]} ${_twoDigit(date.day)}';
}

/// Full day-group heading: `Today`, `Tomorrow`, else `Monday 28`.
String fullDayLabelForOffset(int dayOffset) {
  if (dayOffset == 0) return 'Today';
  if (dayOffset == 1) return 'Tomorrow';
  final date = dateForOffset(dayOffset);
  return '${_weekdayFull[date.weekday]} ${_twoDigit(date.day)}';
}

/// Parse a backend ISO date (`2026-07-23`) into a local [DateTime]. Returns
/// null on a malformed value so a bad row never crashes the board.
DateTime? parseIsoDate(String value) {
  return DateTime.tryParse(value);
}

/// Formats a `HH:MM:SS` (or `HH:MM`) start time as a 12-hour label, e.g.
/// `18:00:00` -> `6:00pm`. Returns the raw value if it can't be parsed.
String formatClockTime(String time) {
  final parts = time.split(':');
  if (parts.length < 2) return time;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return time;
  final suffix = hour >= 12 ? 'pm' : 'am';
  final h12 = hour % 12 == 0 ? 12 : hour % 12;
  return '$h12:${_twoDigit(minute)}$suffix';
}

/// A start-to-end range from a `HH:MM:SS` start and a duration in minutes, e.g.
/// (`18:00:00`, 55) -> `6:00pm - 6:55pm`. Falls back to the start label alone
/// when the start can't be parsed.
String formatSlotRange(String startTime, int durationMinutes) {
  final parts = startTime.split(':');
  if (parts.length < 2) return formatClockTime(startTime);
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return formatClockTime(startTime);
  final start = DateTime(2000, 1, 1, hour, minute);
  final end = start.add(Duration(minutes: durationMinutes));
  return '${formatClockTime(startTime)} - '
      '${formatClockTime('${_twoDigit(end.hour)}:${_twoDigit(end.minute)}')}';
}
