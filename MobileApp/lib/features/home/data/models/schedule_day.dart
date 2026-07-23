import 'package:mobile_app/features/home/data/models/class_occurrence.dart';
import 'package:mobile_app/features/home/data/schedule_dates.dart';

/// One day's slice of the schedule board — the label the day group renders and
/// its occurrences (possibly empty, which the group shows as an empty-day
/// state). [dayOffset] (0 = today) ties the group to its date tab.
class ScheduleDay {
  const ScheduleDay({
    required this.dayOffset,
    required this.label,
    required this.occurrences,
  });

  final int dayOffset;
  final String label;
  final List<ClassOccurrence> occurrences;
}

/// Buckets the board's occurrences into one [ScheduleDay] per window day
/// (0..[windowDays]-1) — every window day gets a group (empty days included)
/// so the date tabs map 1:1 to day groups. Occurrences arrive already
/// time-sorted from the bloc, so each day's list stays in start-time order.
List<ScheduleDay> groupOccurrencesByDay(
  List<ClassOccurrence> occurrences,
  int windowDays,
) {
  final byOffset = <int, List<ClassOccurrence>>{};
  for (final o in occurrences) {
    final date = parseIsoDate(o.classDate);
    if (date == null) continue;
    final offset = dayOffsetForDate(date);
    if (offset < 0 || offset >= windowDays) continue;
    (byOffset[offset] ??= <ClassOccurrence>[]).add(o);
  }
  return [
    for (var i = 0; i < windowDays; i++)
      ScheduleDay(
        dayOffset: i,
        label: fullDayLabelForOffset(i),
        occurrences: byOffset[i] ?? const [],
      ),
  ];
}
