import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/core/navigation/app_routes.dart';
import 'package:app_management/features/schedule/data/mock_schedule.dart';
import 'package:app_management/shared/widgets/class_row/class_card.dart';

/// One day of the schedule, rendered as a column: a day-label header above
/// a vertical stack of [ClassCard]s for that day.
class ScheduleDayColumn extends StatelessWidget {
  final ScheduleDayGroup group;

  const ScheduleDayColumn({super.key, required this.group});

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
                ? DesignConstants.lightPrimary
                : DesignConstants.text,
          ),
        ),
        _DayCards(group: group),
      ],
    );
  }
}

class _DayCards extends StatelessWidget {
  final ScheduleDayGroup group;
  const _DayCards({required this.group});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingLarge,
      children: [
        for (final e in group.classes)
          ClassCard(
            name: e.name,
            timeLabel: e.timeLabel,
            instructorName: e.instructor.fullName,
            instructorPhotoAsset: e.instructor.photoAsset,
            imageAsset: e.imageAsset,
            pointsWorth: e.pointsWorth,
            attendingCount: e.attendingCount,
            onTap: () =>
                Navigator.pushNamed(context, AppRoutes.scheduleEditClass),
          ),
      ],
    );
  }
}
