import 'package:intl/intl.dart';

import 'package:crm/features/home/data/upcoming_classes.dart';
import 'package:crm/features/schedule/data/class_time_format.dart';
import 'package:crm/features/schedule/data/models/effective_class_instance.dart';

/// How many upcoming occurrences the dashboard teaser shows before it cuts off.
/// The full week lives on the Schedule screen.
const int kUpcomingClassesLimit = 12;

final DateFormat _dayLabel = DateFormat('EEEE, MMM d');

/// Day-grouped view models for the dashboard "Upcoming Classes" card, built
/// from the real effective class instances (`GET /api/v1/classes/instances`).
///
/// Filters to non-cancelled occurrences still in the future, sorts by the UTC
/// `occurred_at` instant, caps at [kUpcomingClassesLimit], then groups by the
/// occurrence's local date (a friendly "Today" / "Tomorrow" / weekday label).
List<ScheduledClassDayGroup> upcomingClassesFromInstances(
  List<EffectiveClassInstance> instances,
) {
  final now = DateTime.now();
  final upcoming = instances
      .where((i) => !i.isCancelled && i.occurredAt.isAfter(now))
      .toList()
    ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
  final capped = upcoming.take(kUpcomingClassesLimit);

  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = today.add(const Duration(days: 1));

  final order = <DateTime>[];
  final byDay = <DateTime, List<ScheduledClass>>{};
  for (final i in capped) {
    final day = DateTime(i.classDate.year, i.classDate.month, i.classDate.day);
    final list = byDay.putIfAbsent(day, () {
      order.add(day);
      return <ScheduledClass>[];
    });
    list.add(_entry(i));
  }

  return [
    for (final day in order)
      ScheduledClassDayGroup(
        dayLabel: _labelFor(day, today, tomorrow),
        classes: byDay[day]!,
      ),
  ];
}

String _labelFor(DateTime day, DateTime today, DateTime tomorrow) {
  if (day == today) return 'Today';
  if (day == tomorrow) return 'Tomorrow';
  return _dayLabel.format(day);
}

ScheduledClass _entry(EffectiveClassInstance i) => ScheduledClass(
      id: '${i.classId}_${i.classDate.toIso8601String()}',
      name: i.className,
      timeLabel:
          classTimeRangeLabel(i.resolvedClassTime, i.resolvedDurationMinutes),
      instructorName: i.resolvedInstructorName,
      attendingCount: i.attendanceCount,
      imageUrl: (i.imageUrl?.isEmpty ?? true) ? null : i.imageUrl,
    );
