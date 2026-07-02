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

/// `6:00 PM · Wed, Jul 2` from a `HH:MM:SS` local start time + its date — one
/// occurrence's pickable label. Shared by the member check-in/reserve
/// dialog's occurrence tiles and class-identity cards so both render the
/// same "when" caption.
String classDateTimeLabel(DateTime date, String classTime) {
  final parts = classTime.split(':');
  final hour = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
  final minute = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
  final time = _timeFormat.format(DateTime(2000, 1, 1, hour, minute));
  return '$time · ${_shortDateFormat.format(date)}';
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
