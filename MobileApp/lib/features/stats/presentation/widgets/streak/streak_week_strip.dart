import 'package:flutter/material.dart';
import 'package:mobile_app/features/stats/data/mock_stats.dart';
import 'package:mobile_app/features/stats/presentation/widgets/streak/streak_day_badge.dart';
import 'package:mobile_app/shared/widgets/animation/celebration_timings.dart';

/// Horizontal strip of seven [StreakDayBadge]s — Sunday through Saturday.
/// Cascades each badge in left-to-right after [baseDelay], one per
/// `badgeStagger` window.
class StreakWeekStrip extends StatelessWidget {
  const StreakWeekStrip({
    super.key,
    required this.days,
    this.baseDelay = Duration.zero,
  });

  final List<MockStreakDay> days;
  final Duration baseDelay;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < days.length; i++)
          StreakDayBadge(
            day: days[i],
            delay: baseDelay + CelebrationTimings.badgeStagger * i,
          ),
      ],
    );
  }
}
