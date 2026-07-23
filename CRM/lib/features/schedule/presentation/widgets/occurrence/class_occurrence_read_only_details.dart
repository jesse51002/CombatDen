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
/// detail panel ([DetailField] tiles in a responsive [FillGrid]), plus — when
/// the caller may edit the schedule ([canEdit]) — an "Edit" button that
/// switches to `ClassOccurrenceOverrideSection` and, when [cancellable], a
/// destructive-styled "Cancel this class" button beside it. A tapped
/// occurrence is opened to be SEEN first, not dropped straight into an
/// editable form.
///
/// For a non-owner/admin role ([canEdit] false — trainer or front desk) the
/// Edit/Cancel action row is omitted, leaving a pure read-only detail panel.
/// Front desk instead gets its own reduced cancel/move block
/// (`ClassOccurrenceStaffActions`) via the dedicated occurrence endpoints; a
/// trainer stays fully read-only.
///
/// Always sourced from [entry] (never the editable form state) — a
/// successful save pops the whole screen rather than returning here, so
/// [entry] never goes stale while this is shown.
class ClassOccurrenceReadOnlyDetails extends StatelessWidget {
  final ScheduleClassEntry entry;
  final VoidCallback onEdit;

  /// Whether the Edit / Cancel action row shows at all (owner/admin). When
  /// false the detail panel renders read-only.
  final bool canEdit;

  /// Whether this occurrence can still be cancelled (upcoming, not already
  /// cancelled) — gates the "Cancel this class" button (only relevant when
  /// [canEdit] is true).
  final bool cancellable;
  final VoidCallback onCancel;

  const ClassOccurrenceReadOnlyDetails({
    super.key,
    required this.entry,
    required this.onEdit,
    required this.canEdit,
    required this.cancellable,
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
                label: 'Time',
                value: classTimeRangeLabel(
                  entry.resolvedClassTime,
                  entry.resolvedDurationMinutes,
                ),
                caption: classDurationLabel(entry.resolvedDurationMinutes),
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
          if (canEdit) ...[
            const Hairline(),
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: DesignConstants.spacingLarge,
                children: [
                  if (cancellable)
                    AppOutlineButton(
                      text: 'Cancel this class',
                      onPressed: onCancel,
                      borderColor: DesignConstants.badRed,
                      textColor: DesignConstants.badRed,
                    ),
                  AppOutlineButton(text: 'Edit', onPressed: onEdit),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
