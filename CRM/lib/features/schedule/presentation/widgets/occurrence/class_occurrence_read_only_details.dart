import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/schedule/data/class_time_format.dart';
import 'package:crm/features/schedule/data/models/gym_class_view_models.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/detail_field.dart';
import 'package:crm/shared/widgets/fill_grid.dart';
import 'package:crm/shared/widgets/hairline.dart';
import 'package:crm/shared/widgets/subtitle_section.dart';

final DateFormat _dateLabel = DateFormat('EEEE, MMM d, yyyy');

/// "This day's details" — the occurrence screen's default **view** mode: the
/// occurrence's date / start time / instructor / max capacity as a readable
/// detail panel ([DetailField] tiles in a responsive [FillGrid]), plus an
/// "Edit" button that switches to `ClassOccurrenceOverrideSection`. A tapped
/// occurrence is opened to be SEEN first, not dropped straight into an
/// editable form.
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
          FillGrid(
            minItemWidth: 200,
            children: [
              DetailField(
                icon: Symbols.calendar_month_sharp,
                label: 'Date',
                value: _dateLabel.format(entry.classDate),
              ),
              DetailField(
                icon: Symbols.schedule_sharp,
                label: 'Start time',
                value: time?.format(context) ?? '—',
              ),
              DetailField(
                icon: Symbols.person_sharp,
                label: 'Instructor',
                value: entry.instructorName ?? '—',
              ),
              DetailField(
                icon: Symbols.group_sharp,
                label: 'Max capacity',
                value: entry.maxCapacity != null
                    ? '${entry.maxCapacity}'
                    : 'No limit',
              ),
            ],
          ),
          const Hairline(),
          Align(
            alignment: Alignment.centerRight,
            child: AppOutlineButton(text: 'Edit', onPressed: onEdit),
          ),
        ],
      ),
    );
  }
}
