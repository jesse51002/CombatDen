import 'dart:math';

import 'package:customization_engine/showcase/home/home_class.dart';

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

/// Builds one day's schedule from the const [showcaseClasses] — class i at
/// slot i. Every day shows the same four classes at the same times (per-day
/// variation is just the demo attending/booked flags).
ShowcaseDay dayAt(int dayOffset) {
  return ShowcaseDay(
    label: formatFullDayLabel(dayOffset),
    classes: [
      for (var i = 0; i < showcaseClasses.length; i++)
        ShowcaseClass(
          name: showcaseClasses[i].name,
          timeRange: showcaseClasses[i].timeRange,
          durationMinutes: showcaseClasses[i].durationMinutes,
          mentor: showcaseClasses[i].mentor,
          imageAsset: showcaseClasses[i].imageAsset,
          attending: _seededAttending(dayOffset, i),
          isBooked: _isClassBooked(dayOffset, i),
        ),
    ],
  );
}
