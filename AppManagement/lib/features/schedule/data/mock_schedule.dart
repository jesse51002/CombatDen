import 'package:flutter/material.dart';

/// Models for the gym Schedule screen.
///
/// The screen renders the week as a board of day columns; each column holds
/// that day's classes stacked vertically. [ScheduleClassEntry] is a single
/// rendered card — built live from the selected gym's classes by
/// `schedule_generator.dart`. [ScheduleClass] is the full class *definition*
/// edited by the Add/Edit Class form (still mock — see [kSampleClass]). Field
/// names mirror the `gym_classes` table so the future swap is mechanical.

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

/// One rendered card in a day column. Built from the selected gym's classes
/// (see `schedule_generator.dart`): the gym feed serves the class image and
/// the instructor photo as network URLs, so this carries URLs (not bundled
/// assets) plus the demo-only [pointsWorth] / [attendingCount].
class ScheduleClassEntry {
  final String id;
  final String name;
  final String timeLabel;
  final String instructorName;
  final String? instructorPhotoUrl;
  final String? imageUrl;
  final int? pointsWorth;
  final int? attendingCount;

  const ScheduleClassEntry({
    required this.id,
    required this.name,
    required this.timeLabel,
    required this.instructorName,
    this.instructorPhotoUrl,
    this.imageUrl,
    this.pointsWorth,
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

// The Edit-form prefill keeps a bundled sample image — that form is still
// mock. Only the live schedule board reads the selected gym's network images.
const String _kSampleClassImage = 'assets/images/class_muay_thai_session.png';

/// Sample class used to prefill the Edit Class form in the prototype.
final ScheduleClass kSampleClass = ScheduleClass(
  id: 'sc_001',
  className: 'Muay Thai All Levels',
  description:
      'Striking fundamentals and pad work for every skill level.',
  imageAsset: _kSampleClassImage,
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
