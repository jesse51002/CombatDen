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

/// Builds one day's schedule from the selected gym's live [classes]. Every day
/// shows the *same* four classes — only their time slots rotate by [dayOffset],
/// so a class at 9am today lands at a later slot tomorrow and no two adjacent
/// days look the same. The rotation is a bijection over the slots, so each
/// class still appears exactly once per day. Per-day attending/booked flags add
/// demo texture on top.
MockDay dayAt(int dayOffset, List<ClassInfo> classes) {
  final count = min(_classTimes.length, classes.length);
  return MockDay(
    label: formatFullDayLabel(dayOffset),
    classes: [
      for (var slot = 0; slot < count; slot++)
        _classForSlot(
          dayOffset,
          slot,
          classes[(slot + dayOffset) % count],
        ),
    ],
  );
}

/// One scheduled class: the live [info] placed into the fixed time [slot], with
/// demo-only attending/booked flags seeded per (day, slot).
MockClass _classForSlot(int dayOffset, int slot, ClassInfo info) {
  return MockClass(
    name: info.name,
    timeRange: _classTimes[slot],
    durationMinutes: _kClassDurationMinutes,
    mentor: info.instructorName,
    imageUrl: info.imageUrl,
    description: info.description,
    instructorBio: info.instructorBio,
    instructorImageUrl: info.instructorImageUrl,
    attending: _seededAttending(dayOffset, slot),
    isBooked: _isClassBooked(dayOffset, slot),
  );
}
