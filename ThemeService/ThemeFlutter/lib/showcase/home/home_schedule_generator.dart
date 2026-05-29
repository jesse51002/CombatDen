import 'dart:math';

import 'package:theme_flutter/showcase/home/home_class.dart';
import 'package:theme_flutter/showcase/showcase_content.dart';

/// Clone of MobileApp's `schedule_generator.dart`. Builds one day's schedule
/// by looping the const showcase classes into fixed time slots, with
/// deterministic demo-only attending/booked flags — same as the member app.

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

DateTime _todayMidnight() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

String _twoDigit(int n) => n.toString().padLeft(2, '0');

String formatDayLabel(int dayOffset) {
  if (dayOffset == 0) return 'Today';
  if (dayOffset == 1) return 'Tomorrow';
  final date = _todayMidnight().add(Duration(days: dayOffset));
  return '${_weekdayAbbr[date.weekday]} ${_twoDigit(date.day)}';
}

String formatFullDayLabel(int dayOffset) {
  if (dayOffset == 0) return 'Today';
  if (dayOffset == 1) return 'Tomorrow';
  final date = _todayMidnight().add(Duration(days: dayOffset));
  return '${_weekdayFull[date.weekday]} ${_twoDigit(date.day)}';
}

int _seededAttending(int dayOffset, int classIndex) {
  final seed = dayOffset * 7 + classIndex * 13;
  return 10 + Random(seed).nextInt(31);
}

bool _isClassBooked(int dayOffset, int classIndex) {
  // Deterministic pattern: ~1-2 booked classes per ~3 days, varied across
  // both axes so the visual mix matches the design without real state.
  return (dayOffset * 4 + classIndex) % 7 == 0 ||
      (dayOffset * 3 + classIndex * 2) % 11 == 0;
}

/// The base classes for the schedule: the host's injected gym [classes] when
/// provided (their time slots borrowed from the const samples by index, since
/// the gym file carries no schedule), else the const [showcaseClasses].
List<ShowcaseClass> _baseClasses(List<ShowcaseClassInfo>? classes) {
  if (classes == null || classes.isEmpty) return showcaseClasses;
  return [
    for (var i = 0; i < classes.length; i++)
      ShowcaseClass(
        name: classes[i].name,
        // Borrow a plausible time slot from the samples (gym files have no time).
        timeRange: showcaseClasses[i % showcaseClasses.length].timeRange,
        durationMinutes:
            showcaseClasses[i % showcaseClasses.length].durationMinutes,
        mentor: classes[i].instructorName,
        imageUrl: classes[i].imageUrl,
      ),
  ];
}

/// Builds one day's schedule — class i at slot i. Every day shows the same
/// classes at the same times (per-day variation is just the demo
/// attending/booked flags). Pass [classes] to preview a real gym's classes.
ShowcaseDay dayAt(int dayOffset, {List<ShowcaseClassInfo>? classes}) {
  final base = _baseClasses(classes);
  return ShowcaseDay(
    label: formatFullDayLabel(dayOffset),
    classes: [
      for (var i = 0; i < base.length; i++)
        ShowcaseClass(
          name: base[i].name,
          timeRange: base[i].timeRange,
          durationMinutes: base[i].durationMinutes,
          mentor: base[i].mentor,
          imageAsset: base[i].imageAsset,
          imageUrl: base[i].imageUrl,
          attending: _seededAttending(dayOffset, i),
          isBooked: _isClassBooked(dayOffset, i),
        ),
    ],
  );
}
