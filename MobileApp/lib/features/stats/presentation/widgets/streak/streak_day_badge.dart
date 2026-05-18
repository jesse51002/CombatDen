import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/stats/data/mock_stats.dart';
import 'package:mobile_app/shared/widgets/animation/celebration_timings.dart';
import 'package:mobile_app/shared/widgets/animation/staggered_reveal.dart';

/// One day-of-week pill in the Streak week strip. Completed days get an
/// orange-tinted background and a check; incomplete days are an open circle.
/// Cascades in via [StaggeredReveal] after [delay]; completed badges add a
/// brief scale + alpha pulse on land for a per-day micro-celebration.
class StreakDayBadge extends StatelessWidget {
  const StreakDayBadge({
    super.key,
    required this.day,
    this.delay = Duration.zero,
  });

  final MockStreakDay day;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final letterColor =
        day.completed ? DesignConstants.primaryColor : DesignConstants.text2nd;
    final iconColor =
        day.completed ? DesignConstants.primaryColor : DesignConstants.text2nd;

    final badge = Container(
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
            day.completed ? Symbols.check_circle_sharp : Symbols.circle_sharp,
            weight: DesignConstants.iconWeight,
            color: iconColor,
            size: DesignConstants.iconSizeSm,
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
        final v = _t.value;
        return Transform.scale(scale: 0.9 + 0.1 * v, child: child);
      },
      child: widget.child,
    );
  }
}
