/// Mock data for the gym Schedule screen.
///
/// The Schedule screen renders a 7-day x 13-hour grid (Sun-Sat, 8am-8pm).
/// Each [ScheduleClassBlock] represents a class occupying one or more
/// hour slots in a single day column. Field names mirror what a real API
/// would return so the future swap to a repository is mechanical.
class ScheduleClassBlock {
  final String id;
  final String name;
  final String timeLabel;

  /// 0 = Sunday, 6 = Saturday.
  final int dayIndex;

  /// Hour-of-day the class starts, in 24h. e.g. `11` = 11am, `18` = 6pm.
  /// Must be within the visible range `kScheduleStartHour`..
  /// `kScheduleEndHour`.
  final int startHour;

  /// Whole-hour duration. Most classes are 1 hour.
  final int durationHours;

  const ScheduleClassBlock({
    required this.id,
    required this.name,
    required this.timeLabel,
    required this.dayIndex,
    required this.startHour,
    this.durationHours = 1,
  });
}

class ScheduleWeek {
  final String monthLabel;
  final String rangeLabel;
  final List<ScheduleDay> days;
  final List<ScheduleClassBlock> classes;

  const ScheduleWeek({
    required this.monthLabel,
    required this.rangeLabel,
    required this.days,
    required this.classes,
  });
}

class ScheduleDay {
  /// Three-letter day label as shown in the design (SUN, MON, ...).
  final String label;
  final int dayOfMonth;

  const ScheduleDay({required this.label, required this.dayOfMonth});
}

/// First hour shown in the grid (24h). 8 = 8am.
const int kScheduleStartHour = 8;

/// Last hour shown in the grid (24h, inclusive). 20 = 8pm.
const int kScheduleEndHour = 20;

/// Total visible hour rows. (8am..8pm = 13 rows)
const int kScheduleHourRowCount = kScheduleEndHour - kScheduleStartHour + 1;

const ScheduleWeek kMockScheduleWeek = ScheduleWeek(
  monthLabel: 'February, 2026',
  rangeLabel: 'Feb 1st, 2026 - Feb 7th, 2026',
  days: [
    ScheduleDay(label: 'SUN', dayOfMonth: 1),
    ScheduleDay(label: 'MON', dayOfMonth: 2),
    ScheduleDay(label: 'TUE', dayOfMonth: 3),
    ScheduleDay(label: 'WED', dayOfMonth: 4),
    ScheduleDay(label: 'THR', dayOfMonth: 5),
    ScheduleDay(label: 'FRI', dayOfMonth: 6),
    ScheduleDay(label: 'SAT', dayOfMonth: 7),
  ],
  classes: [
    // 11am - 12pm row
    ScheduleClassBlock(
      id: 'sc_001',
      name: 'Muay Thai All Levels',
      timeLabel: '11am - 12pm',
      dayIndex: 2,
      startHour: 11,
    ),
    ScheduleClassBlock(
      id: 'sc_002',
      name: 'Muay Thai All Levels',
      timeLabel: '11am - 12pm',
      dayIndex: 4,
      startHour: 11,
    ),
    ScheduleClassBlock(
      id: 'sc_003',
      name: 'Muay Thai All Levels',
      timeLabel: '11am - 12pm',
      dayIndex: 6,
      startHour: 11,
    ),
    // 12pm - 1pm row
    ScheduleClassBlock(
      id: 'sc_004',
      name: 'Muay Thai All Levels',
      timeLabel: '12pm - 1pm',
      dayIndex: 1,
      startHour: 12,
    ),
    ScheduleClassBlock(
      id: 'sc_005',
      name: 'Muay Thai All Levels',
      timeLabel: '12pm - 1pm',
      dayIndex: 3,
      startHour: 12,
    ),
    ScheduleClassBlock(
      id: 'sc_006',
      name: 'Open Spar',
      timeLabel: '12pm - 1pm',
      dayIndex: 6,
      startHour: 12,
    ),
    // 5pm - 6pm row (Youth)
    ScheduleClassBlock(
      id: 'sc_007',
      name: 'Youth',
      timeLabel: '5pm - 6pm',
      dayIndex: 1,
      startHour: 17,
    ),
    ScheduleClassBlock(
      id: 'sc_008',
      name: 'Youth',
      timeLabel: '5pm - 6pm',
      dayIndex: 3,
      startHour: 17,
    ),
    // 6pm - 7pm row (Muay Thai everywhere except Sun)
    ScheduleClassBlock(
      id: 'sc_009',
      name: 'Muay Thai All Levels',
      timeLabel: '6pm - 7pm',
      dayIndex: 1,
      startHour: 18,
    ),
    ScheduleClassBlock(
      id: 'sc_010',
      name: 'Muay Thai All Levels',
      timeLabel: '6pm - 7pm',
      dayIndex: 2,
      startHour: 18,
    ),
    ScheduleClassBlock(
      id: 'sc_011',
      name: 'Muay Thai All Levels',
      timeLabel: '6pm - 7pm',
      dayIndex: 3,
      startHour: 18,
    ),
    ScheduleClassBlock(
      id: 'sc_012',
      name: 'Muay Thai All Levels',
      timeLabel: '6pm - 7pm',
      dayIndex: 4,
      startHour: 18,
    ),
    ScheduleClassBlock(
      id: 'sc_013',
      name: 'Muay Thai All Levels',
      timeLabel: '6pm - 7pm',
      dayIndex: 5,
      startHour: 18,
    ),
    // 7pm - 8pm row
    ScheduleClassBlock(
      id: 'sc_014',
      name: 'BJJ NO GI',
      timeLabel: '7pm - 8pm',
      dayIndex: 1,
      startHour: 19,
    ),
    ScheduleClassBlock(
      id: 'sc_015',
      name: 'Cardio Smash / MMA',
      timeLabel: '7pm - 8pm',
      dayIndex: 2,
      startHour: 19,
    ),
    ScheduleClassBlock(
      id: 'sc_016',
      name: 'BJJ NO GI',
      timeLabel: '7pm - 8pm',
      dayIndex: 3,
      startHour: 19,
    ),
    ScheduleClassBlock(
      id: 'sc_017',
      name: 'Cardio Smash / MMA',
      timeLabel: '7pm - 8pm',
      dayIndex: 4,
      startHour: 19,
    ),
  ],
);
