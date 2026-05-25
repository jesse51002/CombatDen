import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/schedule/data/mock_schedule.dart';
import 'package:app_management/shared/widgets/custom_text_field.dart';
import 'package:app_management/shared/widgets/form/app_date_field.dart';
import 'package:app_management/shared/widgets/form/app_dropdown_field.dart';
import 'package:app_management/shared/widgets/form/app_time_field.dart';
import 'package:app_management/shared/widgets/subtitle_section.dart';

/// "Schedule" form section: start time, duration, recurrence, and the
/// active date range.
class ClassScheduleSection extends StatelessWidget {
  final TimeOfDay? classTime;
  final ValueChanged<TimeOfDay> onTimeChanged;
  final TextEditingController durationController;
  final RecurringUnit recurringUnit;
  final ValueChanged<RecurringUnit?> onUnitChanged;
  final TextEditingController intervalController;
  final DateTime? startDate;
  final ValueChanged<DateTime> onStartChanged;
  final DateTime? endDate;
  final ValueChanged<DateTime> onEndChanged;

  const ClassScheduleSection({
    super.key,
    required this.classTime,
    required this.onTimeChanged,
    required this.durationController,
    required this.recurringUnit,
    required this.onUnitChanged,
    required this.intervalController,
    required this.startDate,
    required this.onStartChanged,
    required this.endDate,
    required this.onEndChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SubtitleSection(
      title: 'Schedule',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingLarge,
        children: [
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
                  controller: durationController,
                  label: 'Duration (minutes)',
                  hintText: '60',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingLarge,
            children: [
              Expanded(
                child: AppDropdownField<RecurringUnit>(
                  label: 'Repeats',
                  value: recurringUnit,
                  onChanged: onUnitChanged,
                  items: [
                    for (final u in RecurringUnit.values)
                      if (u != RecurringUnit.unknown)
                        DropdownMenuItem(value: u, child: Text(u.label)),
                  ],
                ),
              ),
              Expanded(
                child: CustomTextField(
                  controller: intervalController,
                  label: 'Every (interval)',
                  hintText: '1',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingLarge,
            children: [
              Expanded(
                child: AppDateField(
                  label: 'Start date',
                  value: startDate,
                  onChanged: onStartChanged,
                ),
              ),
              Expanded(
                child: AppDateField(
                  label: 'End date (optional)',
                  value: endDate,
                  onChanged: onEndChanged,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
