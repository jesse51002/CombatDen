/// The Sunday (local midnight) that starts the week containing today —
/// the initial week for any surface hosting a `ScheduleBloc` (the Schedule
/// board and the dashboard's Live Attendance card).
///
/// TODO(class-system): uses the device date; the gym-local "today" is not yet
/// exposed to the CRM. Revisit once a gym timezone is available client-side.
DateTime currentWeekStart() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return today.subtract(Duration(days: today.weekday % 7));
}
