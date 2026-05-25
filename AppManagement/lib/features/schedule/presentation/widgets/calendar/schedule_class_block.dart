import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';
import 'package:app_management/features/schedule/data/mock_schedule.dart';

/// A single class block placed inside one cell of the schedule grid.
///
/// Visual: card-tinted rounded rectangle with a sapphire accent bottom border,
/// time label on top in [DesignConstants.text2nd] and class name below
/// in [DesignConstants.text].
class ScheduleClassBlockTile extends StatelessWidget {
  final ScheduleClassBlock block;

  const ScheduleClassBlockTile({super.key, required this.block});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => debugPrint('TODO: open class detail'),
      borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignConstants.spacingMedium,
          vertical: DesignConstants.spacingSmall,
        ),
        decoration: BoxDecoration(
          color: DesignConstants.card,
          borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
          border: Border(
            bottom: BorderSide(
              color: DesignConstants.primaryColor,
              width: DesignConstants.buttonBorder,
            ),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: DesignConstants.spacingTiny,
          children: [
            Text(
              block.name,
              style: DesignConstants.h3,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              block.timeLabel,
              style: DesignConstants.pSmall.copyWith(
                color: DesignConstants.text2nd,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
