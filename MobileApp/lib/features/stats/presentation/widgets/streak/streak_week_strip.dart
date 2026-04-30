import 'package:flutter/material.dart';
import 'package:mobile_app/features/stats/data/mock_stats.dart';
import 'package:mobile_app/features/stats/presentation/widgets/streak/streak_day_badge.dart';

/// Horizontal strip of seven [StreakDayBadge]s — Sunday through Saturday.
class StreakWeekStrip extends StatelessWidget {
  const StreakWeekStrip({super.key, required this.days});

  final List<MockStreakDay> days;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (final day in days) StreakDayBadge(day: day),
      ],
    );
  }
}
