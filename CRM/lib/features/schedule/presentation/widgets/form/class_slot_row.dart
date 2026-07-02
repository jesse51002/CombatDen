import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/schedule/data/models/instructor_option.dart';
import 'package:crm/shared/widgets/form/app_dropdown_field.dart';
import 'package:crm/shared/widgets/form/app_time_field.dart';

/// Fixed footprint reserved for a slot row's trailing remove (×) control, so
/// the field columns line up with the [ClassSlotHeaderRow] gutter above them.
const double _kRemoveGutter = DesignConstants.pillControlHeight;

/// One editable schedule slot row — a start-time picker, an instructor
/// picker, and a remove (×) action. The building block of both a weekly
/// day's slot column and the daily/monthly "Times" column
/// (`ClassDaysSection`).
///
/// The columns are labelled once by [ClassSlotHeaderRow] above the list, so
/// the fields render **unlabelled** here — that keeps every repeated row quiet
/// and lets the day heading read as the strongest element in its group (a
/// per-row 16px "Time"/"Instructor" label would out-shout it).
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
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingMedium,
      children: [
        Expanded(
          child: AppTimeField(
            value: time,
            onChanged: onTimeChanged,
          ),
        ),
        Expanded(
          child: AppDropdownField<String>(
            value: instructorId,
            hintText: 'Select instructor',
            onChanged: onInstructorChanged,
            items: [
              for (final i in instructors)
                DropdownMenuItem(value: i.id, child: Text(i.name)),
            ],
          ),
        ),
        SizedBox(
          width: _kRemoveGutter,
          height: _kRemoveGutter,
          child: IconButton(
            onPressed: onRemove,
            tooltip: 'Remove time',
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Symbols.close_sharp,
              size: DesignConstants.iconSizeSmall,
              weight: DesignConstants.iconWeight,
              color: DesignConstants.text2nd,
            ),
          ),
        ),
      ],
    );
  }
}

/// The once-per-list column headers ("Time" / "Instructor") shown above a
/// day's [ClassSlotRow]s. Kept here beside [ClassSlotRow] so the two share the
/// same column shape — two equal [Expanded]s plus the fixed remove-control
/// gutter — and stay aligned. Deliberately quiet (small, muted) so it sits
/// clearly below the day heading in the hierarchy.
class ClassSlotHeaderRow extends StatelessWidget {
  const ClassSlotHeaderRow({super.key});

  @override
  Widget build(BuildContext context) {
    final style = DesignConstants.pSmallSemibold.copyWith(
      color: DesignConstants.text2nd,
    );
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        Expanded(child: Text('Time', style: style)),
        Expanded(child: Text('Instructor', style: style)),
        const SizedBox(width: _kRemoveGutter),
      ],
    );
  }
}
