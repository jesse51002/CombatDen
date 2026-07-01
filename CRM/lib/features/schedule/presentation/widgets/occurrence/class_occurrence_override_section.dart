import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/schedule/data/models/instructor_option.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';
import 'package:crm/shared/widgets/form/app_date_field.dart';
import 'package:crm/shared/widgets/form/app_dropdown_field.dart';
import 'package:crm/shared/widgets/form/app_time_field.dart';
import 'package:crm/shared/widgets/subtitle_section.dart';

/// "This day's details" — the occurrence screen's editable overrides:
/// instructor, start time, max capacity, and date for just this occurrence.
/// Pre-filled by the caller with the occurrence's current effective values;
/// Save dispatches a single-date instance-exception override (see [onSave]);
/// Cancel discards the in-progress edits and returns to the read-only view
/// (see [onCancel]).
///
/// The **date** field reschedules the occurrence to another day: it defaults
/// to [originalDate] (no move) and its picker floors at `originalDate + 1
/// day` — the backend's reschedule is **forward-only** (a DB CHECK) and also
/// rejects a collision with an existing occurrence. Scope note: this assumes
/// [originalDate] is the occurrence's original, not-yet-moved date;
/// rescheduling an already-rescheduled occurrence a second time is out of
/// scope.
class ClassOccurrenceOverrideSection extends StatelessWidget {
  final String? instructorId;
  final ValueChanged<String?> onInstructorChanged;
  final List<InstructorOption> instructors;
  final TimeOfDay? classTime;
  final ValueChanged<TimeOfDay> onTimeChanged;
  final TextEditingController capacityController;
  final DateTime originalDate;
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
    required this.capacityController,
    required this.originalDate,
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingLarge,
            children: [
              Expanded(
                child: AppTimeField(
                  label: 'Start time',
                  value: classTime,
                  onChanged: onTimeChanged,
                ),
              ),
              Expanded(
                child: CustomTextField(
                  controller: capacityController,
                  label: 'Max capacity',
                  hintText: '24',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingSmall,
            children: [
              AppDateField(
                label: 'Date',
                value: selectedDate,
                firstDate: originalDate.add(const Duration(days: 1)),
                onChanged: onDateChanged,
              ),
              Text(
                'A class can only be moved to a later date.',
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
