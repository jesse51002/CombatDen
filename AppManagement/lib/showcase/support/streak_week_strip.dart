import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:app_management/showcase/showcase_tokens.dart';
import 'package:app_management/showcase/support/staggered_reveal.dart';
import 'package:theme_flutter/theme/animation/celebration_timings.dart';

/// One day in the streak week strip (clone of MobileApp's `MockStreakDay`).
class ShowcaseStreakDay {
  const ShowcaseStreakDay({required this.label, required this.completed});
  final String label;
  final bool completed;
}

/// Clone of MobileApp's `StreakWeekStrip`: seven [_StreakDayBadge]s, Sunday
/// through Saturday, cascading in left-to-right after [baseDelay].
class StreakWeekStrip extends StatelessWidget {
  const StreakWeekStrip({
    super.key,
    required this.days,
    this.baseDelay = Duration.zero,
  });

  final List<ShowcaseStreakDay> days;
  final Duration baseDelay;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < days.length; i++)
          _StreakDayBadge(
            day: days[i],
            delay: baseDelay + CelebrationTimings.badgeStagger * i,
          ),
      ],
    );
  }
}

/// Clone of MobileApp's `StreakDayBadge`. Completed days get a brand-tinted
/// background + check and a brief scale pulse on land.
class _StreakDayBadge extends StatelessWidget {
  const _StreakDayBadge({required this.day, this.delay = Duration.zero});

  final ShowcaseStreakDay day;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final color = day.completed
        ? ShowcaseTokens.primaryColor
        : ShowcaseTokens.text2nd;

    final badge = Container(
      // Narrower horizontal padding so all seven badges fit the device
      // width without overflowing; keep the taller vertical padding for the
      // day-pill look.
      padding: const EdgeInsets.symmetric(
        horizontal: ShowcaseTokens.spacingMedium,
        vertical: ShowcaseTokens.paddingSmall,
      ),
      decoration: BoxDecoration(
        color: day.completed
            ? ShowcaseTokens.primaryCard
            : ShowcaseTokens.backgroundColor,
        borderRadius: BorderRadius.circular(ShowcaseTokens.radiusSmall),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: ShowcaseTokens.spacingSmall,
        children: [
          Text(day.label, style: ShowcaseTokens.h2.copyWith(color: color)),
          Icon(
            day.completed ? Symbols.check_circle_sharp : Symbols.circle_sharp,
            weight: ShowcaseTokens.iconWeight,
            color: color,
            size: ShowcaseTokens.iconSizeSm,
          ),
        ],
      ),
    );

    return StaggeredReveal(
      delay: delay,
      child: day.completed ? _PulseOnLand(delay: delay, child: badge) : badge,
    );
  }
}

class _PulseOnLand extends StatefulWidget {
  const _PulseOnLand({required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  State<_PulseOnLand> createState() => _PulseOnLandState();
}

class _PulseOnLandState extends State<_PulseOnLand>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: CelebrationTimings.pulseDuration,
  );

  late final Animation<double> _t = CurvedAnimation(
    parent: _ctrl,
    curve: Curves.easeOutQuart,
  );

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _ctrl.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _ctrl.forward();
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) {
        return Transform.scale(scale: 0.9 + 0.1 * _t.value, child: child);
      },
      child: widget.child,
    );
  }
}
