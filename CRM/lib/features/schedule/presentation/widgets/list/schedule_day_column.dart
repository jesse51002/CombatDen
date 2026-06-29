import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/schedule/data/models/gym_class_view_models.dart';
import 'package:crm/shared/widgets/class_row/class_card.dart';

/// One day of the schedule, rendered as a column: a day-label header above
/// a vertical stack of [ClassCard]s for that day.
///
/// [onClassTap] is called with a card's [ScheduleClassEntry] when tapped; the
/// board opens the manage dialog (edit the class, or cancel just that day),
/// sharing the board's bloc.
class ScheduleDayColumn extends StatelessWidget {
  final ScheduleDayGroup group;
  final void Function(ScheduleClassEntry entry) onClassTap;

  const ScheduleDayColumn({
    super.key,
    required this.group,
    required this.onClassTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text(
          group.dayLabel,
          style: DesignConstants.h2.copyWith(
            color: group.isToday
                ? DesignConstants.primaryColor
                : DesignConstants.text,
          ),
        ),
        _DayCards(group: group, onClassTap: onClassTap),
      ],
    );
  }
}

class _DayCards extends StatelessWidget {
  final ScheduleDayGroup group;
  final void Function(ScheduleClassEntry entry) onClassTap;

  const _DayCards({required this.group, required this.onClassTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        for (final e in group.classes)
          ClassCard(
            name: e.name,
            timeLabel: e.timeLabel,
            instructorName: e.instructorName,
            imageUrl: e.imageUrl,
            pointsWorth: e.pointsWorth,
            attendingCount: e.attendingCount,
            isCancelled: e.isCancelled,
            onTap: () => onClassTap(e),
          ),
      ],
    );
  }
}
