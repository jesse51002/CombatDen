import 'package:crm/features/schedule/data/class_time_format.dart';
import 'package:crm/features/schedule/data/models/gym_class_response.dart';
import 'package:crm/features/schedule/data/models/recurring_unit.dart';

/// Weekday key (`sun`..`sat`) → short label. Daily/monthly schedules use the
/// reserved `"all"` key, which carries no weekday prefix.
const Map<String, String> _dayAbbrev = {
  'sun': 'Sun',
  'mon': 'Mon',
  'tue': 'Tue',
  'wed': 'Wed',
  'thu': 'Thu',
  'fri': 'Fri',
  'sat': 'Sat',
};

/// One class an employee leads — a view model for the detail page (NOT a JSON
/// model). [slotLabels] holds one entry per weekly session (e.g.
/// "Mon · 6:00 AM - 7:00 AM"); its length is this class's weekly-session count
/// for that instructor. [cadenceLabel] describes how the class recurs.
class EmployeeTaughtClass {
  final String className;
  final String cadenceLabel;
  final List<String> slotLabels;

  const EmployeeTaughtClass({
    required this.className,
    required this.cadenceLabel,
    required this.slotLabels,
  });

  /// Groups every gym class's per-slot instructor assignments by instructor id
  /// (`gym_employees.employee_id`) so the directory can show what each employee
  /// actually runs. Walks each class's [GymClassResponse.weekdaySlots]
  /// (day → ordered slots, each with an optional `instructorId`) and buckets by
  /// that id; a slot with no instructor is skipped.
  static Map<String, List<EmployeeTaughtClass>> deriveByInstructor(
    List<GymClassResponse> classes,
  ) {
    final acc = <String, Map<String, _Accum>>{};
    for (final c in classes) {
      for (final entry in c.weekdaySlots.entries) {
        for (final slot in entry.value) {
          final id = slot.instructorId;
          if (id == null) continue;
          final byClass = acc.putIfAbsent(id, () => {});
          final a = byClass.putIfAbsent(c.classId, () => _Accum(c));
          a.slotLabels.add(
            _slotLabel(entry.key, slot.time, c.durationMinutes),
          );
        }
      }
    }
    return acc.map((id, byClass) {
      final list = byClass.values.map((a) => a.build()).toList()
        ..sort((x, y) =>
            x.className.toLowerCase().compareTo(y.className.toLowerCase()));
      return MapEntry(id, list);
    });
  }

  static String _slotLabel(String dayKey, String time, int duration) {
    final range = classTimeRangeLabel(time, duration);
    final day = _dayAbbrev[dayKey];
    return day == null ? range : '$day · $range';
  }

  static String _cadenceLabel(GymClassResponse c) {
    final n = c.recurringInterval;
    switch (c.recurringUnit) {
      case RecurringUnit.weekly:
        return n <= 1 ? 'Weekly' : 'Every $n weeks';
      case RecurringUnit.daily:
        return n <= 1 ? 'Daily' : 'Every $n days';
      case RecurringUnit.monthly:
        return n <= 1 ? 'Monthly' : 'Every $n months';
      case RecurringUnit.unknown:
        return 'Recurring';
    }
  }
}

/// Mutable accumulator while grouping slots per (instructor, class).
class _Accum {
  final GymClassResponse gymClass;
  final List<String> slotLabels = [];

  _Accum(this.gymClass);

  EmployeeTaughtClass build() => EmployeeTaughtClass(
        className: gymClass.className,
        cadenceLabel: EmployeeTaughtClass._cadenceLabel(gymClass),
        slotLabels: slotLabels,
      );
}
