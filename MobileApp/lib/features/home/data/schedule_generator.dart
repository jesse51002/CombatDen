import 'dart:math';

import 'package:mobile_app/features/class_booking/data/class_info.dart';
import 'package:mobile_app/features/home/data/mock_class_schedule.dart';

/// The four daily time slots. The VideoService returns four classes; we keep
/// these fixed times and loop the classes into them, one per slot.
const _classTimes = <String>[
  '9:00am - 9:55am',
  '11:00am - 11:55am',
  '6:00pm - 6:55pm',
  '7:00pm - 7:55pm',
];
const _kClassDurationMinutes = 55;

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

/// Builds one day's schedule by looping the live [classes] into the fixed
/// time slots — class i at slot i. Every day shows the same four classes at
/// the same times (per-day variation is just the demo attending/booked flags).
MockDay dayAt(int dayOffset, List<ClassInfo> classes) {
  final count = min(_classTimes.length, classes.length);
  return MockDay(
    label: formatFullDayLabel(dayOffset),
    classes: [
      for (var i = 0; i < count; i++)
        MockClass(
          name: classes[i].name,
          timeRange: _classTimes[i],
          durationMinutes: _kClassDurationMinutes,
          mentor: classes[i].instructorName,
          imageUrl: classes[i].imageUrl,
          description: classes[i].description,
          instructorBio: classes[i].instructorBio,
          instructorImageUrl: classes[i].instructorImageUrl,
          attending: _seededAttending(dayOffset, i),
          isBooked: _isClassBooked(dayOffset, i),
        ),
    ],
  );
}
