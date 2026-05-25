import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/core/navigation/app_routes.dart';
import 'package:app_management/features/home/data/mock_upcoming_classes.dart';
import 'package:app_management/shared/widgets/class_row/class_row.dart';

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
          timeLabel: '${c.startTime} - ${c.endTime} (${c.durationLabel})',
          instructorName: c.instructorName,
          imageAsset: c.imageAsset,
          attendingCount: c.attendingCount,
          checkedInCount: c.checkedInCount,
          inSession: c.inSession,
          onTap: () => Navigator.pushNamed(context, AppRoutes.schedule),
        ),
      );
      children.add(Container(height: 1, color: DesignConstants.divider));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: children,
    );
  }
}
