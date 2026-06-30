import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/schedule/data/models/instructor_option.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';
import 'package:crm/shared/widgets/custom_text_field.dart';
import 'package:crm/shared/widgets/form/app_dropdown_field.dart';
import 'package:crm/shared/widgets/form/app_time_field.dart';
import 'package:crm/shared/widgets/subtitle_section.dart';

/// "This day's details" — the occurrence screen's editable overrides:
/// instructor, start time, and max capacity for just this date. Pre-filled by
/// the caller with the occurrence's current effective values; Save dispatches
/// a single-date instance-exception override (see [onSave]).
class ClassOccurrenceOverrideSection extends StatelessWidget {
  final String? instructorId;
  final ValueChanged<String?> onInstructorChanged;
  final List<InstructorOption> instructors;
  final TimeOfDay? classTime;
  final ValueChanged<TimeOfDay> onTimeChanged;
  final TextEditingController capacityController;
  final VoidCallback onSave;

  const ClassOccurrenceOverrideSection({
    super.key,
    required this.instructorId,
    required this.onInstructorChanged,
    required this.instructors,
    required this.classTime,
    required this.onTimeChanged,
    required this.capacityController,
    required this.onSave,
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
          Align(
            alignment: Alignment.centerRight,
            child: AppPrimaryButton(
              text: 'Save changes',
              onPressed: onSave,
            ),
          ),
        ],
      ),
    );
  }
}
