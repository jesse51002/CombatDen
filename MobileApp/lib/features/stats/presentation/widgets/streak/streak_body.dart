import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/design_constants.dart';
import 'package:mobile_app/features/stats/data/mock_stats.dart';
import 'package:mobile_app/features/stats/presentation/widgets/streak/streak_week_strip.dart';

/// Big "3" + "week streak" headline, sub-copy, and the week strip.
class StreakBody extends StatelessWidget {
  const StreakBody({super.key, required this.stats});

  final MockStreakStats stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DesignConstants.spacingBig,
      children: [
        Text(
          '${stats.weekCount}',
          textAlign: TextAlign.center,
          style: DesignConstants.big1,
        ),
        Text(
          'week streak',
          textAlign: TextAlign.center,
          style: DesignConstants.big2,
        ),
        Text(
          stats.subtitle,
          textAlign: TextAlign.center,
          style: DesignConstants.pBig.copyWith(color: DesignConstants.text2nd),
        ),
        StreakWeekStrip(days: stats.weekDays),
      ],
    );
  }
}
