import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/schedule/data/mock_instructors.dart';
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
class ClassDaysSection extends StatelessWidget {
  final Set<int> selectedDays;
  final ValueChanged<int> onToggleDay;
  final Map<int, String?> instructorByDay;
  final void Function(int day, String? employeeId) onInstructorChanged;

  const ClassDaysSection({
    super.key,
    required this.selectedDays,
    required this.onToggleDay,
    required this.instructorByDay,
    required this.onInstructorChanged,
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
          for (final day in activeDays)
            AppDropdownField<String>(
              label: '${_dayNames[day]} instructor',
              value: instructorByDay[day],
              hintText: 'Select instructor',
              onChanged: (id) => onInstructorChanged(day, id),
              items: [
                for (final i in kMockInstructors)
                  DropdownMenuItem(
                    value: i.employeeId,
                    child: Text(i.fullName),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
