import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/check_in/check_in_class_group.dart';
import 'package:crm/features/schedule/data/class_time_format.dart';
import 'package:crm/shared/widgets/class_row/class_card.dart';
import 'package:crm/shared/widgets/fill_grid.dart';

/// Identity-level picker: one image [ClassCard] per distinct class, reused
/// as-is from the schedule board (16:9 image, graceful no-image fallback)
/// so a class reads the same here as it does on the board. Tapping a card
/// calls [onSelect] with that class's id; the caller drills into its
/// occurrences next — there's no in-grid "selected" state since a tap
/// navigates immediately.
///
/// [hintPrefix] captions each card with its representative occurrence
/// ("Next" for a reservable class, "Last" for a past one) — the group's
/// [CheckInClassGroup.representative] is already the soonest/most-recent
/// occurrence per the caller's sort order.
class CheckInClassPicker extends StatelessWidget {
  final List<CheckInClassGroup> groups;
  final String hintPrefix;
  final String emptyLabel;
  final ValueChanged<String> onSelect;

  const CheckInClassPicker({
    super.key,
    required this.groups,
    required this.hintPrefix,
    required this.emptyLabel,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return Text(
        emptyLabel,
        style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
      );
    }
    return FillGrid(
      minItemWidth: 220,
      minColumns: 2,
      children: [
        for (final group in groups)
          ClassCard(
            name: group.className,
            timeLabel: '$hintPrefix '
                '${classDateTimeLabel(
                  group.representative.classDate,
                  group.representative.resolvedClassTime,
                )}',
            imageUrl: group.imageUrl,
            pointsWorth: group.representative.pointsWorth,
            onTap: () => onSelect(group.classId),
          ),
      ],
    );
  }
}
