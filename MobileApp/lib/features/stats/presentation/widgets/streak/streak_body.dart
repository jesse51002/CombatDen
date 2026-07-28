import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/stats/data/mock_stats.dart';
import 'package:mobile_app/features/stats/presentation/widgets/streak/streak_week_strip.dart';
import 'package:mobile_app/shared/widgets/animation/celebration_timings.dart';
import 'package:mobile_app/shared/widgets/animation/count_up_text.dart';
import 'package:mobile_app/shared/widgets/animation/staggered_reveal.dart';
import 'package:mobile_app/shared/widgets/api_image.dart';
import 'package:theme_flutter/theme/theme_image.dart';
import 'package:mobile_app/shared/widgets/post_class/intro/celebration_intro_stage.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_controller.dart';

/// Streak celebration. The one-shot that plays first is the tenant's
/// `celebration_intro` — `orbit` by default, the ring of streak marks
/// that expands, collapses, and pops the icon. Whichever value is
/// active, the same settled block arrives once it is done: the week
/// count, "week streak", the subtitle, and the week strip, cascading in
/// as one centred focal group.
///
/// The intro moves the streak mark; the settled block never contains it.
/// That is why an intro can be swapped without touching this card's
/// content — see `shared/widgets/post_class/intro/`.
class StreakBody extends StatelessWidget {
  const StreakBody({super.key, required this.stats, this.controller});

  final MockStreakStats stats;
  final PostClassController? controller;

  @override
  Widget build(BuildContext context) {
    final mark = ThemeImage.image(
      CombatDenSlots.streakIcon,
      fallback: ApiImage.asset('streak_icon.png'),
    );
    return CelebrationIntroStage(
      hero: mark,
      particle: mark,
      controller: controller,
      settled: (context, captureOffset) =>
          _StatsContent(stats: stats, captureOffset: captureOffset),
    );
  }
}

class _StatsContent extends StatelessWidget {
  const _StatsContent({required this.stats, this.captureOffset});

  final MockStreakStats stats;

  /// Set only under capture: this block's absolute start on the global
  /// capture timeline (= the active intro's hand-off point). Null in
  /// normal app use.
  final Duration? captureOffset;

  @override
  Widget build(BuildContext context) {
    final base = captureOffset ?? Duration.zero;
    final subtitleDelay = base + CelebrationTimings.countUpDuration;
    final stripDelay = subtitleDelay + CelebrationTimings.revealStagger;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingLarge,
      children: [
        _MainStatement(weekCount: stats.weekCount, captureOffset: captureOffset),
        StaggeredReveal(
          delay: subtitleDelay,
          child: Text(
            stats.subtitle,
            textAlign: TextAlign.center,
            style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
          ),
        ),
        StreakWeekStrip(days: stats.weekDays, baseDelay: stripDelay),
      ],
    );
  }
}

class _MainStatement extends StatelessWidget {
  const _MainStatement({required this.weekCount, this.captureOffset});

  final int weekCount;

  /// Set only under capture: this block's absolute start on the global
  /// capture timeline (= the active intro's hand-off point). Null in
  /// normal app use.
  final Duration? captureOffset;

  @override
  Widget build(BuildContext context) {
    return StaggeredReveal(
      delay: captureOffset ?? Duration.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CountUpText(
            target: weekCount,
            delay: captureOffset ?? Duration.zero,
            style: DesignConstants.big1,
            textAlign: TextAlign.center,
          ),
          Text(
            'week streak',
            textAlign: TextAlign.center,
            style: DesignConstants.big2,
          ),
        ],
      ),
    );
  }
}
