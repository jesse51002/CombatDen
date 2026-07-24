// Pure helpers for the Reports & exports month/year pickers — kept out of the
// widget so the range logic stays small and self-evident.

/// Full month names, index 0 = January. Used for the picker items and the
/// dynamic `Download <Month> <Year>` button label.
const List<String> kReportMonthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// The fallback earliest year when the gym's `created_at` isn't known (an
/// older backend not yet returning it). CombatDen has no gym data before this.
const int kReportFallbackFloorYear = 2025;

/// The selectable years, ascending, from the gym's creation year (or
/// [kReportFallbackFloorYear] when [gymCreatedAt] is null) up to [now]'s year.
/// A gym created "in the future" (clock skew) collapses to just the current
/// year so the list is never empty or reversed.
List<int> reportYears(DateTime? gymCreatedAt, DateTime now) {
  final floor = gymCreatedAt?.year ?? kReportFallbackFloorYear;
  final start = floor > now.year ? now.year : floor;
  return [for (var y = start; y <= now.year; y++) y];
}

/// The highest selectable month for [year]: the current month when [year] is
/// the current year (no future months), else December — so a report is never
/// requested for a month that hasn't started.
int maxMonthForYear(int year, DateTime now) {
  return year == now.year ? now.month : 12;
}
