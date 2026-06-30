import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/navigation/app_routes.dart';
import 'package:crm/features/home/data/upcoming_classes.dart';
import 'package:crm/shared/widgets/class_row/class_row.dart';

/// One day section inside the Upcoming Classes card: day label header
/// followed by the list of classes for that day, each separated by a
/// thin divider.
class ClassDayGroup extends StatelessWidget {
  final ScheduledClassDayGroup group;

  const ClassDayGroup({super.key, required this.group});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        Text(group.dayLabel, style: DesignConstants.h2),
        _ClassesList(group: group),
      ],
    );
  }
}

class _ClassesList extends StatelessWidget {
  final ScheduledClassDayGroup group;
  const _ClassesList({required this.group});

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final c in group.classes) {
      children.add(
        ClassRow(
          name: c.name,
          timeLabel: c.timeLabel,
          instructorName: c.instructorName,
          imageUrl: c.imageUrl,
          attendingCount: c.attendingCount,
          onTap: () => Navigator.pushNamed(context, AppRoutes.schedule),
        ),
      );
      children.add(
        Container(
          height: DesignConstants.dividerThickness,
          color: DesignConstants.divider,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: children,
    );
  }
}
