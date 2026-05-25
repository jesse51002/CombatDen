import 'package:flutter/material.dart';

import 'package:app_management/features/schedule/data/mock_instructors.dart';

/// Mock data for the gym Schedule screen.
///
/// The screen renders the week as a board of day columns; each column holds
/// that day's classes stacked vertically. [ScheduleClassEntry] is a single
/// rendered card; [ScheduleClass] is the full class *definition* edited by
/// the Add/Edit Class form. Field names mirror the `gym_classes` table so
/// the future swap to a repository is mechanical.

/// `gym_classes.recurring_unit`. Includes an [unknown] fallback for when
/// real JSON arrives.
enum RecurringUnit {
  daily,
  weekly,
  monthly,
  unknown;

  String get label {
    switch (this) {
      case RecurringUnit.daily:
        return 'Daily';
      case RecurringUnit.weekly:
        return 'Weekly';
      case RecurringUnit.monthly:
        return 'Monthly';
      case RecurringUnit.unknown:
        return 'Custom';
    }
  }
}

/// Full class definition — the shape the Add/Edit Class form reads and
/// writes. Mirrors `gym_classes` including per-day instructor assignment.
class ScheduleClass {
  final String id;
  final String className;
  final String? description;
  final String? imageAsset;
  final int pointsWorth;
  final int? maxCapacity;
  final TimeOfDay classTime;
  final int durationMinutes;
  final RecurringUnit recurringUnit;
  final int recurringInterval;

  /// Active day indices, 0 = Sunday .. 6 = Saturday (the `sun..sat` flags).
  final Set<int> activeDays;

  /// Instructor employeeId per day index (the `*_instructor_id` columns).
  final Map<int, String?> instructorIdByDay;

  final DateTime startDate;
  final DateTime? endDate;

  const ScheduleClass({
    required this.id,
    required this.className,
    this.description,
    this.imageAsset,
    this.pointsWorth = 50,
    this.maxCapacity,
    required this.classTime,
    required this.durationMinutes,
    this.recurringUnit = RecurringUnit.weekly,
    this.recurringInterval = 1,
    this.activeDays = const {},
    this.instructorIdByDay = const {},
    required this.startDate,
    this.endDate,
  });
}

/// One rendered card in a day column.
class ScheduleClassEntry {
  final String id;
  final String name;
  final String timeLabel;
  final Instructor instructor;
  final String imageAsset;
  final int pointsWorth;
  final int? attendingCount;

  const ScheduleClassEntry({
    required this.id,
    required this.name,
    required this.timeLabel,
    required this.instructor,
    required this.imageAsset,
    this.pointsWorth = 50,
    this.attendingCount,
  });
}

class ScheduleDayGroup {
  final String dayLabel;
  final List<ScheduleClassEntry> classes;

  /// Marks the current day so its column header is highlighted.
  final bool isToday;

  const ScheduleDayGroup({
    required this.dayLabel,
    required this.classes,
    this.isToday = false,
  });
}

/// Week label shown in the header bar.
const String kScheduleMonthLabel = 'February, 2026';
const String kScheduleRangeLabel = 'Feb 1st, 2026 - Feb 7th, 2026';

// Class images are reused across classes as generic gym action shots in
// this prototype (we only have muay thai / BJJ photos bundled).
const String _imgMuayThaiA = 'assets/images/class_muay_thai_session.png';
const String _imgMuayThaiB = 'assets/images/class_muay_thai_wed.png';
const String _imgMuayThaiC = 'assets/images/class_muay_thai_thu.png';
const String _imgBjjA = 'assets/images/class_bjj_nogi_today.png';
const String _imgBjjB = 'assets/images/class_bjj_nogi_wed.png';
const String _imgBjjC = 'assets/images/class_bjj_nogi_thu.png';

/// Sample class used to prefill the Edit Class form in the prototype.
final ScheduleClass kSampleClass = ScheduleClass(
  id: 'sc_001',
  className: 'Muay Thai All Levels',
  description:
      'Striking fundamentals and pad work for every skill level.',
  imageAsset: _imgMuayThaiA,
  pointsWorth: 50,
  maxCapacity: 24,
  classTime: const TimeOfDay(hour: 18, minute: 0),
  durationMinutes: 60,
  recurringUnit: RecurringUnit.weekly,
  recurringInterval: 1,
  activeDays: const {1, 3, 5},
  instructorIdByDay: const {
    1: 'emp_001',
    3: 'emp_002',
    5: 'emp_001',
  },
  startDate: DateTime(2026, 2, 1),
);

final List<ScheduleDayGroup> kMockScheduleDays = [
  ScheduleDayGroup(
    dayLabel: 'Sun, Feb 1',
    classes: [
      ScheduleClassEntry(
        id: 'e_001',
        name: 'Open Mat',
        timeLabel: '10:00am - 12:00pm',
        instructor: kInstructorJustin,
        imageAsset: _imgBjjC,
        pointsWorth: 30,
        attendingCount: 8,
      ),
      ScheduleClassEntry(
        id: 'e_002',
        name: 'Muay Thai All Levels',
        timeLabel: '12:00pm - 1:00pm',
        instructor: kInstructorAmy,
        imageAsset: _imgMuayThaiC,
        pointsWorth: 50,
        attendingCount: 14,
      ),
    ],
  ),
  ScheduleDayGroup(
    dayLabel: 'Mon, Feb 2',
    classes: [
      ScheduleClassEntry(
        id: 'e_003',
        name: 'Muay Thai All Levels',
        timeLabel: '12:00pm - 1:00pm',
        instructor: kInstructorJustin,
        imageAsset: _imgMuayThaiB,
        pointsWorth: 50,
        attendingCount: 18,
      ),
      ScheduleClassEntry(
        id: 'e_004',
        name: 'Youth',
        timeLabel: '5:00pm - 6:00pm',
        instructor: kInstructorAmy,
        imageAsset: _imgMuayThaiA,
        pointsWorth: 40,
        attendingCount: 12,
      ),
      ScheduleClassEntry(
        id: 'e_005',
        name: 'Muay Thai All Levels',
        timeLabel: '6:00pm - 7:00pm',
        instructor: kInstructorBen,
        imageAsset: _imgMuayThaiC,
        pointsWorth: 50,
        attendingCount: 27,
      ),
    ],
  ),
  ScheduleDayGroup(
    dayLabel: 'Tue, Feb 3',
    classes: [
      ScheduleClassEntry(
        id: 'e_006',
        name: 'Muay Thai All Levels',
        timeLabel: '11:00am - 12:00pm',
        instructor: kInstructorLily,
        imageAsset: _imgMuayThaiC,
        pointsWorth: 50,
        attendingCount: 15,
      ),
      ScheduleClassEntry(
        id: 'e_007',
        name: 'Cardio Smash / MMA',
        timeLabel: '7:00pm - 8:00pm',
        instructor: kInstructorTimothy,
        imageAsset: _imgBjjA,
        pointsWorth: 60,
        attendingCount: 22,
      ),
    ],
  ),
  ScheduleDayGroup(
    dayLabel: 'Wed, Feb 4',
    isToday: true,
    classes: [
      ScheduleClassEntry(
        id: 'e_008',
        name: 'Youth',
        timeLabel: '5:00pm - 6:00pm',
        instructor: kInstructorAmy,
        imageAsset: _imgMuayThaiB,
        pointsWorth: 40,
        attendingCount: 14,
      ),
      ScheduleClassEntry(
        id: 'e_009',
        name: 'BJJ NO GI',
        timeLabel: '7:00pm - 8:00pm',
        instructor: kInstructorBen,
        imageAsset: _imgBjjB,
        pointsWorth: 55,
        attendingCount: 19,
      ),
    ],
  ),
  ScheduleDayGroup(
    dayLabel: 'Thu, Feb 5',
    classes: [
      ScheduleClassEntry(
        id: 'e_010',
        name: 'Muay Thai All Levels',
        timeLabel: '6:00pm - 7:00pm',
        instructor: kInstructorJustin,
        imageAsset: _imgMuayThaiC,
        pointsWorth: 50,
        attendingCount: 25,
      ),
      ScheduleClassEntry(
        id: 'e_011',
        name: 'BJJ NO GI',
        timeLabel: '7:00pm - 8:00pm',
        instructor: kInstructorLily,
        imageAsset: _imgBjjC,
        pointsWorth: 55,
        attendingCount: 16,
      ),
    ],
  ),
  ScheduleDayGroup(
    dayLabel: 'Fri, Feb 6',
    classes: [
      ScheduleClassEntry(
        id: 'e_012',
        name: 'Open Spar',
        timeLabel: '12:00pm - 1:00pm',
        instructor: kInstructorTimothy,
        imageAsset: _imgMuayThaiA,
        pointsWorth: 45,
        attendingCount: 9,
      ),
      ScheduleClassEntry(
        id: 'e_013',
        name: 'Muay Thai All Levels',
        timeLabel: '6:00pm - 7:00pm',
        instructor: kInstructorBen,
        imageAsset: _imgMuayThaiB,
        pointsWorth: 50,
        attendingCount: 28,
      ),
    ],
  ),
  ScheduleDayGroup(
    dayLabel: 'Sat, Feb 7',
    classes: [
      ScheduleClassEntry(
        id: 'e_014',
        name: 'Muay Thai All Levels',
        timeLabel: '10:00am - 11:00am',
        instructor: kInstructorBen,
        imageAsset: _imgMuayThaiA,
        pointsWorth: 50,
        attendingCount: 20,
      ),
      ScheduleClassEntry(
        id: 'e_015',
        name: 'Open Spar',
        timeLabel: '11:00am - 12:00pm',
        instructor: kInstructorTimothy,
        imageAsset: _imgBjjA,
        pointsWorth: 45,
        attendingCount: 10,
      ),
    ],
  ),
];
