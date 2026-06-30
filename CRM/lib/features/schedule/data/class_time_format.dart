import 'package:intl/intl.dart';

final DateFormat _timeFormat = DateFormat.jm();

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
