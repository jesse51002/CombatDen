import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/home/data/mock_upcoming_classes.dart';
import 'package:app_management/features/home/presentation/widgets/upcoming_classes_card/_class_day_group.dart';

/// Right-hand panel under the hero: a day-grouped list of upcoming
/// classes, each with a thumbnail and instructor.
class UpcomingClassesCard extends StatelessWidget {
  final List<ScheduledClassDayGroup> dayGroups;

  const UpcomingClassesCard({super.key, required this.dayGroups});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingBig,
      children: [
        Text('Upcoming Classes', style: DesignConstants.h1),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingLarge,
          children: [
            for (final g in dayGroups) ClassDayGroup(group: g),
          ],
        ),
      ],
    );
  }
}
