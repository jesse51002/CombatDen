import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/check_in/check_in_reserve_selection.dart';
import 'package:crm/features/member_details/presentation/dialogs/check_in/check_in_section.dart';
import 'package:crm/features/schedule/data/class_time_format.dart';
import 'package:crm/features/schedule/data/models/effective_class_instance.dart';
import 'package:crm/shared/widgets/class_row/class_card.dart';
import 'package:crm/shared/widgets/fill_grid.dart';

/// Occurrence-level card grid for the Check-in view's CURRENT step: one
/// image [ClassCard] per check-in-able occurrence — NOT a class-identity
/// group (a class with two in-window slots shows two cards), unlike
/// `CheckInClassPicker`, whose grid layout this mirrors so the Check-in and
/// Reserve views feel identical. Each card's caption is the occurrence's
/// EFFECTIVE date + start–end time range (that's when the member is walking
/// in), and tapping a card DIRECTLY selects that occurrence for check-in —
/// no drill-in step, preserving the front-desk one-tap flow. The pick
/// highlights via [ClassCard.selected], keyed by the same
/// [CheckInSection.keyFor] composite the occurrence tiles use.
class CheckInOccurrenceCardGrid extends StatelessWidget {
  final List<EffectiveClassInstance> instances;
  final String? selectedKey;
  final ValueChanged<CheckInReserveSelection> onSelect;
  final String emptyLabel;

  const CheckInOccurrenceCardGrid({
    super.key,
    required this.instances,
    required this.onSelect,
    this.selectedKey,
    required this.emptyLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (instances.isEmpty) {
      return Text(
        emptyLabel,
        style:
            DesignConstants.h3Regular.copyWith(color: DesignConstants.text2nd),
      );
    }
    return FillGrid(
      minItemWidth: 220,
      minColumns: 2,
      children: [
        for (final i in instances)
          ClassCard(
            name: i.className,
            timeLabel: classDateTimeRangeLabel(
              i.classDate,
              i.resolvedClassTime,
              i.resolvedDurationMinutes,
            ),
            imageUrl: i.imageUrl,
            pointsWorth: i.pointsWorth,
            large: true,
            selected:
                CheckInSection.keyFor(CheckInReserveAction.checkIn, i) ==
                    selectedKey,
            onTap: () => onSelect(
              CheckInReserveSelection(
                instance: i,
                action: CheckInReserveAction.checkIn,
              ),
            ),
          ),
      ],
    );
  }
}
