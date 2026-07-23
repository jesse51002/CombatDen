import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final DateFormat _timeFormat = DateFormat.jm();
final DateFormat _shortDateFormat = DateFormat('EEE, MMM d');

/// `6:00 PM - 7:00 PM` from a `HH:MM:SS` local start time + a duration in
/// minutes. The anchor date is arbitrary (formatting only) — no timezone is
/// applied; the inputs are already gym-local. Shared by the schedule board and
/// the dashboard's Upcoming Classes card so both render the same time label.
String classTimeRangeLabel(String classTime, int durationMinutes) {
  final parts = classTime.split(':');
  final hour = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
  final minute = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
  final start = DateTime(2000, 1, 1, hour, minute);
  final end = start.add(Duration(minutes: durationMinutes));
  return '${_timeFormat.format(start)} - ${_timeFormat.format(end)}';
}

/// `6:00 PM - 7:00 PM · Wed, Jul 2` from a `HH:MM:SS` local start time, a
/// duration in minutes, and its date — one occurrence's pickable label with
/// its full time RANGE. Reuses [classTimeRangeLabel] for the start–end half
/// so every surface renders the same range style, then appends the short
/// date. Shared by the member check-in/reserve dialog's occurrence tiles,
/// the class-identity picker cards, and the member class-history rows.
String classDateTimeRangeLabel(
  DateTime date,
  String classTime,
  int durationMinutes,
) =>
    '${classTimeRangeLabel(classTime, durationMinutes)}'
    ' · ${_shortDateFormat.format(date)}';

/// `6:00 PM` — one occurrence's local START time alone, from a `HH:MM:SS`
/// gym-local time. The anchor date is arbitrary (formatting only). For rows
/// that already carry the day in words (the kiosk's "Today · 6:00 PM").
String classStartTimeLabel(String classTime) {
  final parts = classTime.split(':');
  final hour = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
  final minute = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
  return _timeFormat.format(DateTime(2000, 1, 1, hour, minute));
}

/// `6:00 PM · Wed, Jul 2` — one occurrence's START time + short date, no
/// end-time range. For compact list rows where the range is noise (the
/// member class-history card).
String classDateTimeStartLabel(DateTime date, String classTime) =>
    '${classStartTimeLabel(classTime)} · ${_shortDateFormat.format(date)}';

/// `1 hr` / `1 hr 30 min` / `45 min` — a class occurrence's length as a short
/// human caption. Used beside a start–end range where the exact duration is
/// worth calling out (e.g. the occurrence screen's "Time" detail).
String classDurationLabel(int durationMinutes) {
  final hours = durationMinutes ~/ 60;
  final minutes = durationMinutes % 60;
  final hoursLabel = hours == 1 ? '1 hr' : '$hours hrs';
  if (hours == 0) return '$minutes min';
  if (minutes == 0) return hoursLabel;
  return '$hoursLabel $minutes min';
}

/// `HH:MM:SS` (seconds ignored) -> [TimeOfDay], or null on a malformed
/// string. Shared by the series editor and the occurrence-edit screen's time
/// pickers.
TimeOfDay? parseHmsTime(String hms) {
  final parts = hms.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return TimeOfDay(hour: h, minute: m);
}

/// [TimeOfDay] -> `HH:MM:SS`, the backend's local-time wire format.
String formatTimeOfDayHms(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:'
    '${t.minute.toString().padLeft(2, '0')}:00';
