import 'dart:math';

import 'package:crm/features/members/data/gym_detail.dart';
import 'package:crm/features/schedule/data/mock_schedule.dart';

/// Builds the Schedule screen's week board from the **selected gym's** classes.
///
/// The gym contributes the only classes shown — the same instances every day.
/// Each day drops those classes into the fixed [_classTimes] slots under a
/// different permutation, so a class sits at a different time each day and no
/// two day columns are identical. The class image, instructor, and instructor
/// photo travel with the class; only the time, the demo attending count, and a
/// stable per-class points value are assigned here.

/// The four daily time slots. The gym feed carries no schedule, so the board
/// borrows these plausible gym-day times and rotates the classes through them.
const _classTimes = <String>[
  '6:00am - 7:00am',
  '12:00pm - 1:00pm',
  '5:00pm - 6:00pm',
  '7:00pm - 8:00pm',
];

/// The visible week (matches the header's "Feb 1st - Feb 7th" range); Wed is
/// flagged today so its column header highlights, same as before.
const _weekDayLabels = <String>[
  'Sun, Feb 1',
  'Mon, Feb 2',
  'Tue, Feb 3',
  'Wed, Feb 4',
  'Thu, Feb 5',
  'Fri, Feb 6',
  'Sat, Feb 7',
];
const _todayIndex = 3; // Wed, Feb 4

/// A stable per-class points worth, cycled by class index — a class is worth
/// the same points wherever it lands in the week (demo texture, no feed field).
const _pointsByClass = <int>[50, 40, 60, 45];

int _pointsForClass(int classIndex) =>
    _pointsByClass[classIndex % _pointsByClass.length];

/// Seeded attending count (8..30), varied across both axes so the board has a
/// realistic mix without real bookings.
int _seededAttending(int dayIndex, int slot) {
  final seed = dayIndex * 7 + slot * 13;
  return 8 + Random(seed).nextInt(23);
}

/// The class index placed at each time slot on [dayIndex]. A rotation gives a
/// different ordering per day, but with only [count] classes it repeats every
/// [count] days — which would make columns identical on the 7-wide board. So
/// the rotation is reversed on alternating cycles, keeping all seven distinct.
List<int> _dayOrder(int dayIndex, int count) {
  final rotated = [for (var i = 0; i < count; i++) (i + dayIndex) % count];
  final flip = (dayIndex ~/ count).isOdd;
  return flip ? rotated.reversed.toList() : rotated;
}

/// One week of [ScheduleDayGroup]s drawn from [classes] (the selected gym's).
List<ScheduleDayGroup> gymScheduleDays(List<GymClass> classes) {
  final count = min(_classTimes.length, classes.length);
  final days = <ScheduleDayGroup>[];
  for (var day = 0; day < _weekDayLabels.length; day++) {
    final order = _dayOrder(day, count);
    final entries = <ScheduleClassEntry>[];
    for (var slot = 0; slot < count; slot++) {
      final classIndex = order[slot];
      final c = classes[classIndex];
      entries.add(
        ScheduleClassEntry(
          id: 'sched_${day}_$slot',
          name: c.name,
          timeLabel: _classTimes[slot],
          instructorName: c.instructorName,
          // Empty -> null so the avatar shows initials instead of attempting
          // to load an empty URL (the feed defaults missing photos to '').
          instructorPhotoUrl: c.instructorImageUrl.isEmpty
              ? null
              : c.instructorImageUrl,
          imageUrl: c.imageUrl,
          pointsWorth: _pointsForClass(classIndex),
          attendingCount: _seededAttending(day, slot),
        ),
      );
    }
    days.add(
      ScheduleDayGroup(
        dayLabel: _weekDayLabels[day],
        isToday: day == _todayIndex,
        classes: entries,
      ),
    );
  }
  return days;
}
