import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mobile_app/core/constants/design_constants.dart';
import 'package:mobile_app/features/stats/data/mock_stats.dart';

/// One day-of-week pill in the Streak week strip. Completed days get an
/// orange-tinted background and a check; incomplete days are an open circle.
class StreakDayBadge extends StatelessWidget {
  const StreakDayBadge({super.key, required this.day});

  final MockStreakDay day;

  @override
  Widget build(BuildContext context) {
    final letterColor = day.completed
        ? DesignConstants.primaryColor
        : DesignConstants.text2nd;
    final iconColor = day.completed
        ? DesignConstants.primaryColor
        : DesignConstants.text2nd;

    return Container(
      padding: EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: day.completed
            ? DesignConstants.primaryColor25
            : DesignConstants.backgroundColor,
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingSmall,
        children: [
          Text(
            day.label,
            style: DesignConstants.h2.copyWith(color: letterColor),
          ),
          Icon(
            day.completed
                ? Symbols.check_circle_sharp
                : Symbols.circle_sharp,
            weight: DesignConstants.iconWeight,
            color: iconColor,
            size: DesignConstants.iconSizeSm,
          ),
        ],
      ),
    );
  }
}
