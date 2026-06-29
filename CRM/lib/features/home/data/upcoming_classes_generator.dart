import 'dart:math';

import 'package:crm/features/home/data/upcoming_classes.dart';
import 'package:crm/features/members/data/gym_detail.dart';

/// Builds the dashboard "Upcoming Classes" card from the **selected gym's**
/// classes. Each day shows all of the gym's classes dropped into the fixed
/// time [_slots] under a per-day rotation, so a class sits at a different time
/// each day and no two days look the same. The first class of the first day is
/// flagged in-session (a live, checked-in count); the rest carry a seeded
/// attending count. This dashboard teaser is still mock; the Schedule screen
/// itself now reads the real backend (`GET /api/v1/classes/instances`).

class _Slot {
  final String start;
  final String end;
  final String duration;
  const _Slot(this.start, this.end, this.duration);
}

const _slots = <_Slot>[
  _Slot('6:00am', '6:55am', '55 min'),
  _Slot('12:00pm', '12:55pm', '55 min'),
  _Slot('5:00pm', '5:55pm', '55 min'),
  _Slot('7:00pm', '7:55pm', '55 min'),
];

/// The teaser shows the next three days. Relative labels keep the demo stable
/// (no real date math).
const _dayLabels = <String>['Today', 'Tomorrow', 'Wednesday'];

/// A seeded count in [base, base + span), varied across both axes so the card
/// has a realistic mix without real bookings.
int _seeded(int dayIndex, int slot, int base, int span) {
  final seed = dayIndex * 7 + slot * 13;
  return base + Random(seed).nextInt(span);
}

/// The class index placed at each slot on [dayIndex] — a rotation, reversed on
/// alternating cycles so the days stay distinct.
List<int> _dayOrder(int dayIndex, int count) {
  final rotated = [for (var i = 0; i < count; i++) (i + dayIndex) % count];
  final flip = (dayIndex ~/ count).isOdd;
  return flip ? rotated.reversed.toList() : rotated;
}

/// Day-grouped upcoming classes drawn from [classes] (the selected gym's).
List<ScheduledClassDayGroup> gymUpcomingClasses(List<GymClass> classes) {
  final count = min(_slots.length, classes.length);
  final groups = <ScheduledClassDayGroup>[];
  for (var day = 0; day < _dayLabels.length; day++) {
    final order = _dayOrder(day, count);
    final entries = <ScheduledClass>[];
    for (var slot = 0; slot < count; slot++) {
      final c = classes[order[slot]];
      final s = _slots[slot];
      // The very first upcoming class is shown live (in session).
      final live = day == 0 && slot == 0;
      entries.add(
        ScheduledClass(
          id: 'up_${day}_$slot',
          name: c.name,
          startTime: s.start,
          endTime: s.end,
          durationLabel: s.duration,
          instructorName: c.instructorName,
          inSession: live,
          checkedInCount: live ? _seeded(day, slot, 10, 20) : null,
          attendingCount: live ? null : _seeded(day, slot, 8, 23),
          imageUrl: c.imageUrl.isEmpty ? null : c.imageUrl,
        ),
      );
    }
    groups.add(
      ScheduledClassDayGroup(dayLabel: _dayLabels[day], classes: entries),
    );
  }
  return groups;
}
