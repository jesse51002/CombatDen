import 'dart:math';

import 'package:mobile_app/features/home/data/mock_class_schedule.dart';

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

const _muayThaiImages = <String>[
  'class_muay_thai_today.png',
  'class_muay_thai_wed.png',
  'class_muay_thai_thr.png',
];

const _bjjImages = <String>[
  'class_bjj_today.png',
  'class_bjj_wed.png',
  'class_bjj_thr.png',
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

MockDay dayAt(int dayOffset) {
  final morningIndex = dayOffset % _muayThaiImages.length;
  final eveningIndex = (dayOffset + 1) % _muayThaiImages.length;
  return MockDay(
    label: formatFullDayLabel(dayOffset),
    classes: [
      MockClass(
        name: 'Muay Thai',
        timeRange: '9:00am - 9:55am',
        durationMinutes: 55,
        mentor: 'Andy Zerger',
        imageAsset: _muayThaiImages[morningIndex],
        attending: _seededAttending(dayOffset, 0),
        isBooked: _isClassBooked(dayOffset, 0),
      ),
      MockClass(
        name: 'BJJ NO-GI',
        timeRange: '11:00am - 11:55am',
        durationMinutes: 55,
        mentor: 'Andy Zerger',
        imageAsset: _bjjImages[morningIndex],
        attending: _seededAttending(dayOffset, 1),
        isBooked: _isClassBooked(dayOffset, 1),
      ),
      MockClass(
        name: 'Muay Thai',
        timeRange: '6:00pm - 6:55pm',
        durationMinutes: 55,
        mentor: 'Andy Zerger',
        imageAsset: _muayThaiImages[eveningIndex],
        attending: _seededAttending(dayOffset, 2),
        isBooked: _isClassBooked(dayOffset, 2),
      ),
      MockClass(
        name: 'BJJ NO-GI',
        timeRange: '7:00pm - 7:55pm',
        durationMinutes: 55,
        mentor: 'Andy Zerger',
        imageAsset: _bjjImages[eveningIndex],
        attending: _seededAttending(dayOffset, 3),
        isBooked: _isClassBooked(dayOffset, 3),
      ),
    ],
  );
}
