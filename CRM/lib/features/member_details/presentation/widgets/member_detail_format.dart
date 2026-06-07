import 'package:intl/intl.dart';

/// Small presentation-only formatting helpers shared by the
/// member-detail sections and dialogs. No business logic —
/// just consistent date / money strings so every billing
/// surface reads the same.

final DateFormat _dayFormat = DateFormat('MMM d, yyyy');
final DateFormat _dayTimeFormat = DateFormat('MMM d, yyyy · h:mm a');
final DateFormat _shortDayFormat = DateFormat('M/d');

/// `Jun 3, 2026` — or an em dash when null.
String formatDay(DateTime? date) =>
    date == null ? '—' : _dayFormat.format(date.toLocal());

/// `6/3` — a compact month/day, e.g. for inline exit-date
/// labels. Returns an em dash when null.
String formatShortDay(DateTime? date) =>
    date == null ? '—' : _shortDayFormat.format(date.toLocal());

/// `Jun 3, 2026 · 2:14 PM` — or an em dash when null.
String formatDayTime(DateTime? date) =>
    date == null ? '—' : _dayTimeFormat.format(date.toLocal());

/// Parses a user-typed dollar amount (e.g. `49.99`, `$49`,
/// `1,200`) into signed minor units (cents). Returns null
/// when the text is not a positive money value.
int? parseDollarsToCents(String raw) {
  final cleaned =
      raw.replaceAll(RegExp(r'[\$,\s]'), '').trim();
  if (cleaned.isEmpty) return null;
  final value = double.tryParse(cleaned);
  if (value == null || value <= 0) return null;
  return (value * 100).round();
}

/// Title-cases a single token like `active` → `Active`.
String titleCase(String value) {
  if (value.isEmpty) return value;
  return value[0].toUpperCase() + value.substring(1).toLowerCase();
}
