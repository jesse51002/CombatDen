import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/schedule/data/models/instructor_option.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';
import 'package:crm/shared/widgets/form/app_date_field.dart';
import 'package:crm/shared/widgets/form/app_dropdown_field.dart';
import 'package:crm/shared/widgets/form/app_switch_field.dart';
import 'package:crm/shared/widgets/form/app_time_field.dart';
import 'package:crm/shared/widgets/subtitle_section.dart';

/// "This day's details" — the occurrence screen's editable overrides:
/// instructor, start time, duration, an opt-in max capacity, and date for
/// just this occurrence. Pre-filled by the caller with the occurrence's
/// current effective values; Save dispatches a single-date
/// instance-exception override (see [onSave]); Cancel discards the
/// in-progress edits and returns to the read-only view (see [onCancel]).
///
/// [capacityEnabled] gates whether a limit applies at all — the number field
/// only renders when it's on, so there's never a fake placeholder number
/// implying a default cap; off means truly unlimited for this occurrence.
///
/// The **date** field reschedules the occurrence to another day: it defaults
/// to the occurrence's current date (no move) and accepts ANY date. Moving to
/// a future date clears the occurrence's check-ins; moving to a past/today date
/// keeps them, re-dated onto the new day (the backend handles this). The move
/// is rejected only when the exact target date + time is already taken.
class ClassOccurrenceOverrideSection extends StatelessWidget {
  final String? instructorId;
  final ValueChanged<String?> onInstructorChanged;
  final List<InstructorOption> instructors;
  final TimeOfDay? classTime;
  final ValueChanged<TimeOfDay> onTimeChanged;
  final TextEditingController durationController;
  final TextEditingController capacityController;
  final bool capacityEnabled;
  final ValueChanged<bool> onCapacityEnabledChanged;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateChanged;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  const ClassOccurrenceOverrideSection({
    super.key,
    required this.instructorId,
    required this.onInstructorChanged,
    required this.instructors,
    required this.classTime,
    required this.onTimeChanged,
    required this.durationController,
    required this.capacityController,
    required this.capacityEnabled,
    required this.onCapacityEnabledChanged,
    required this.selectedDate,
    required this.onDateChanged,
    required this.onSave,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return SubtitleSection(
      title: "This day's details",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingLarge,
        children: [
          AppDropdownField<String>(
            label: 'Instructor',
            value: instructorId,
            hintText: 'Select instructor',
            onChanged: onInstructorChanged,
            items: [
              for (final i in instructors)
                DropdownMenuItem(value: i.id, child: Text(i.name)),
            ],
          ),
          AppTimeField(
            label: 'Start time',
            value: classTime,
            onChanged: onTimeChanged,
          ),
          CustomTextField(
            controller: durationController,
            label: 'Duration (minutes)',
            hintText: 'e.g. 60',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          AppSwitchField(
            label: 'Limit capacity',
            subtitle: 'Off = unlimited spots',
            value: capacityEnabled,
            onChanged: onCapacityEnabledChanged,
          ),
          if (capacityEnabled)
            CustomTextField(
              controller: capacityController,
              label: 'Max capacity',
              hintText: 'Number of spots',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingSmall,
            children: [
              AppDateField(
                label: 'Date',
                value: selectedDate,
                onChanged: onDateChanged,
              ),
              Text(
                'Move this occurrence to any date. A future date clears its '
                'check-ins; a past/today date keeps them on the new day.',
                style: DesignConstants.pSmall
                    .copyWith(color: DesignConstants.text2nd),
              ),
            ],
          ),
          Row(
            spacing: DesignConstants.spacingLarge,
            children: [
              const Spacer(),
              AppOutlineButton(text: 'Cancel', onPressed: onCancel),
              AppPrimaryButton(text: 'Save changes', onPressed: onSave),
            ],
          ),
        ],
      ),
    );
  }
}
