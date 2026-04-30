import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/home/data/mock_upcoming_classes.dart';
import 'package:app_management/features/home/presentation/widgets/upcoming_classes_card/_class_row.dart';

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
    for (var i = 0; i < group.classes.length; i++) {
      children.add(ClassRow(scheduledClass: group.classes[i]));
      children.add(Container(height: 1, color: DesignConstants.divider));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingMedium,
      children: children,
    );
  }
}
