import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/home/data/mock_class_schedule.dart';

/// When the class runs.
///
/// Its own widget because the spine treatment hoists the time out of the
/// meta column into a leading gutter. Moving one widget keeps the time
/// rendered exactly once; re-typing the text in the gutter would render
/// it twice, which is an added element, not an arrangement.
class ClassItemTime extends StatelessWidget {
  const ClassItemTime({
    super.key,
    required this.classData,
    this.stacked = false,
  });

  final MockClass classData;

  /// Gutter form: start time over the duration, two short lines.
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    if (!stacked) {
      return Text(
        '${classData.timeRange} (${classData.durationMinutes} min)',
        style: DesignConstants.p,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingTiny,
      children: [
        Text(
          classData.timeRange.split(' - ').first,
          style: DesignConstants.h3,
        ),
        Text(
          '${classData.durationMinutes} min',
          style: DesignConstants.pSmall.copyWith(
            color: DesignConstants.text2nd,
          ),
        ),
      ],
    );
  }
}
