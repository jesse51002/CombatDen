import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/schedule/data/models/instructor_option.dart';
import 'package:crm/shared/widgets/form/app_dropdown_field.dart';
import 'package:crm/shared/widgets/form/day_of_week_selector.dart';
import 'package:crm/shared/widgets/subtitle_section.dart';

const List<String> _dayNames = [
  'Sunday', 'Monday', 'Tuesday', 'Wednesday',
  'Thursday', 'Friday', 'Saturday',
];

/// "Days & instructors" form section: pick the active weekdays, then
/// assign an instructor per active day (mirrors the per-day instructor
/// columns on `gym_classes`).
///
/// [instructors] is the gym's real instructor roster, derived from the
/// (id, name) pairs already resolved on its classes — see [InstructorOption].
class ClassDaysSection extends StatelessWidget {
  final Set<int> selectedDays;
  final ValueChanged<int> onToggleDay;
  final Map<int, String?> instructorByDay;
  final void Function(int day, String? employeeId) onInstructorChanged;
  final List<InstructorOption> instructors;

  const ClassDaysSection({
    super.key,
    required this.selectedDays,
    required this.onToggleDay,
    required this.instructorByDay,
    required this.onInstructorChanged,
    required this.instructors,
  });

  @override
  Widget build(BuildContext context) {
    final activeDays = selectedDays.toList()..sort();
    return SubtitleSection(
      title: 'Days & instructors',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingLarge,
        children: [
          DayOfWeekSelector(
            selectedDays: selectedDays,
            onToggle: onToggleDay,
          ),
          if (activeDays.isNotEmpty && instructors.isEmpty)
            Text(
              'No instructors found yet — assign one to a class to build the '
              'roster. You can still save without an instructor.',
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.text2nd,
              ),
            ),
          for (final day in activeDays)
            AppDropdownField<String>(
              label: '${_dayNames[day]} instructor',
              value: instructorByDay[day],
              hintText: 'Select instructor',
              onChanged: (id) => onInstructorChanged(day, id),
              items: [
                for (final i in instructors)
                  DropdownMenuItem(
                    value: i.id,
                    child: Text(i.name),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
