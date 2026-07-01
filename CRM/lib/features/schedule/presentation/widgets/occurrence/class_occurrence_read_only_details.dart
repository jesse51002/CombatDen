import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/schedule/data/class_time_format.dart';
import 'package:crm/features/schedule/data/models/gym_class_view_models.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/info_row.dart';
import 'package:crm/shared/widgets/subtitle_section.dart';

final DateFormat _dateLabel = DateFormat('EEEE, MMM d, yyyy');

/// "This day's details" — the occurrence screen's default **view** mode: the
/// occurrence's start time / instructor / max capacity / date as read-only
/// label/value rows, plus an "Edit" button that switches to
/// `ClassOccurrenceOverrideSection`. A tapped occurrence is opened to be SEEN
/// first, not dropped straight into an editable form.
///
/// Always sourced from [entry] (never the editable form state) — a
/// successful save pops the whole screen rather than returning here, so
/// [entry] never goes stale while this is shown.
class ClassOccurrenceReadOnlyDetails extends StatelessWidget {
  final ScheduleClassEntry entry;
  final VoidCallback onEdit;

  const ClassOccurrenceReadOnlyDetails({
    super.key,
    required this.entry,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final time = parseHmsTime(entry.resolvedClassTime);
    return SubtitleSection(
      title: "This day's details",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingLarge,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingSmall,
            children: [
              InfoRow(
                label: 'Date',
                value: _dateLabel.format(entry.classDate),
              ),
              InfoRow(
                label: 'Start time',
                value: time?.format(context),
              ),
              InfoRow(label: 'Instructor', value: entry.instructorName),
              InfoRow(
                label: 'Max capacity',
                value: entry.maxCapacity != null
                    ? '${entry.maxCapacity}'
                    : 'No limit',
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: AppOutlineButton(text: 'Edit', onPressed: onEdit),
          ),
        ],
      ),
    );
  }
}
