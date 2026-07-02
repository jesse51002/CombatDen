import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/schedule/data/models/instructor_option.dart';
import 'package:crm/shared/widgets/form/app_dropdown_field.dart';
import 'package:crm/shared/widgets/form/app_time_field.dart';

/// One editable schedule slot row — a start-time picker, an instructor
/// picker, and a remove (×) action. The building block of both a weekly
/// day's slot column and the daily/monthly "Times" column
/// (`ClassDaysSection`).
class ClassSlotRow extends StatelessWidget {
  final TimeOfDay? time;
  final String? instructorId;
  final List<InstructorOption> instructors;
  final ValueChanged<TimeOfDay> onTimeChanged;
  final ValueChanged<String?> onInstructorChanged;
  final VoidCallback onRemove;

  const ClassSlotRow({
    super.key,
    required this.time,
    required this.instructorId,
    required this.instructors,
    required this.onTimeChanged,
    required this.onInstructorChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      spacing: DesignConstants.spacingMedium,
      children: [
        Expanded(
          child: AppTimeField(
            label: 'Time',
            value: time,
            onChanged: onTimeChanged,
          ),
        ),
        Expanded(
          child: AppDropdownField<String>(
            label: 'Instructor',
            value: instructorId,
            hintText: 'Select instructor',
            onChanged: onInstructorChanged,
            items: [
              for (final i in instructors)
                DropdownMenuItem(value: i.id, child: Text(i.name)),
            ],
          ),
        ),
        Padding(
          padding:
              const EdgeInsets.only(bottom: DesignConstants.spacingSmall),
          child: IconButton(
            onPressed: onRemove,
            tooltip: 'Remove time',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Symbols.close_sharp,
              size: DesignConstants.iconSizeSmall,
              weight: DesignConstants.iconWeight,
              color: DesignConstants.badRed,
            ),
          ),
        ),
      ],
    );
  }
}
