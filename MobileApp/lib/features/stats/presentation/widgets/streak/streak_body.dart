import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/stats/data/mock_stats.dart';
import 'package:mobile_app/features/stats/presentation/widgets/streak/streak_week_strip.dart';
import 'package:mobile_app/shared/widgets/animation/celebration_timings.dart';
import 'package:mobile_app/shared/widgets/animation/count_up_text.dart';
import 'package:mobile_app/shared/widgets/animation/staggered_reveal.dart';
import 'package:mobile_app/shared/widgets/api_image.dart';
import 'package:customization_engine/theme/theme_image.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_controller.dart';

// Per-screen layout/timing math, file-scoped per CLAUDE.md's _k carve-out.
const Duration _kDelay = Duration(milliseconds: 500);
// The icon pop-in and the ring expansion play together across this window.
const Duration _kGrow = Duration(milliseconds: 700);
const Duration _kHold = Duration(milliseconds: 1500);
const Duration _kCollapse = Duration(milliseconds: 600);
const int _kStarCount = 10;
const double _kSpinTurns = 1.6;
const double _kStarSize = 30;
const double _kIconSize = 120;
// Reference extent the seed sizes were tuned against; render scale is
// `extent / _kReferenceExtent` so larger screens scale proportionally.
const double _kReferenceExtent = 280;
const double _kEdgePad = 28;

/// Streak celebration. A pure-Flutter intro (`_StreakOrbit`) pops the streak
/// icon out at center, expands a continuously-rotating ring of star particles
/// outward around it, then collapses ring + icon away; once the intro finishes
/// the week-count + "week streak" + subtitle + week strip cascade in as one
/// centered focal block.
class StreakBody extends StatefulWidget {
  const StreakBody({super.key, required this.stats, this.controller});

  final MockStreakStats stats;
  final PostClassController? controller;

  @override
  State<StreakBody> createState() => _StreakBodyState();
}

class _StreakBodyState extends State<StreakBody> {
  bool _showStats = false;

  @override
  void initState() {
    super.initState();
    widget.controller?.registerSkipHandler(_skipToFinal);
  }

  void _skipToFinal() => _toStats();

  void _toStats() {
    if (!mounted || _showStats) return;
    setState(() => _showStats = true);
    widget.controller?.markDone();
  }

  @override
  void dispose() {
    widget.controller?.clearSkipHandler();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showStats) {
      return _StatsContent(stats: widget.stats);
    }
    // The orbit intro plays the pop → expand → collapse beats; when it
    // finishes we cross into the stats cascade.
    return SizedBox.expand(child: _StreakOrbit(onComplete: _toStats));
  }
}

/// The intro animation: a single controller drives four beats —
/// 1. **Delay**: a short beat of empty space before anything appears.
/// 2. **Grow**: the streak icon pops in (scale + fade) *while* a ring of star
///    particles expands outward around it — both play together, spinning.
/// 3. **Hold**: the ring rests at full radius, still spinning.
/// 4. **Collapse**: ring radius + icon both shrink and fade to nothing.
///
/// Fills its parent's bounds via `LayoutBuilder` so radius/sizes scale to the
/// available area, mirroring the points screen's `_PointSphere`.
class _StreakOrbit extends StatefulWidget {
  const _StreakOrbit({required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<_StreakOrbit> createState() => _StreakOrbitState();
}

class _StreakOrbitState extends State<_StreakOrbit>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: _kDelay + _kGrow + _kHold + _kCollapse,
    );
    _ctrl.forward().whenComplete(widget.onComplete);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final smallerExtent =
            math.min(constraints.maxWidth, constraints.maxHeight);
        final renderScale = smallerExtent / _kReferenceExtent;
        final starSize = _kStarSize * renderScale;
        final iconSize = _kIconSize * renderScale;
        final maxRadius = smallerExtent / 2 - _kEdgePad - starSize / 2;

        return AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final t = _ctrl.value;
            final totalMs = (_kDelay + _kGrow + _kHold + _kCollapse)
                .inMilliseconds
                .toDouble();
            final delayEnd = _kDelay.inMilliseconds / totalMs;
            final growEnd = (_kDelay + _kGrow).inMilliseconds / totalMs;
            final collapseStart =
                (_kDelay + _kGrow + _kHold).inMilliseconds / totalMs;

            // The icon pop and the ring expansion share one progress value, so
            // they play simultaneously across the grow window.
            final growT =
                ((t - delayEnd) / (growEnd - delayEnd)).clamp(0.0, 1.0);
            final collapseT =
                ((t - collapseStart) / (1 - collapseStart)).clamp(0.0, 1.0);

            final expandE = Curves.easeOutQuart.transform(growT);
            final collapseE = Curves.easeInQuart.transform(collapseT);

            // 0 → 1 (grow), 1 (hold), 1 → 0 (collapse).
            final radiusFactor = expandE * (1 - collapseE);
            final radius = maxRadius * radiusFactor;
            final spin = t * 2 * math.pi * _kSpinTurns;

            // Icon scales in from nothing with a slight overshoot pop, then
            // shrinks back as it fades out during the collapse.
            final popScale = Curves.easeOutBack.transform(growT);
            final iconScale = popScale * (1 - 0.4 * collapseE);
            final iconOpacity =
                Curves.easeOut.transform(growT) * (1 - collapseE);

            return Stack(
              alignment: Alignment.center,
              children: [
                for (var i = 0; i < _kStarCount; i++)
                  _star(i, spin, radius, radiusFactor, starSize),
                _icon(iconScale, iconOpacity, iconSize),
              ],
            );
          },
        );
      },
    );
  }

  Widget _star(
    int i,
    double spin,
    double radius,
    double opacity,
    double size,
  ) {
    final theta = spin + i * 2 * math.pi / _kStarCount;
    return Transform.translate(
      offset: Offset(math.cos(theta) * radius, math.sin(theta) * radius),
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Image(
          image: ThemeImage.image(
            CombatDenSlots.singlePoint,
            fallback: ApiImage.asset('single_point.png'),
          ),
          width: size,
          height: size,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  Widget _icon(double scale, double opacity, double size) {
    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: Transform.scale(
        scale: scale,
        child: Image(
          image: ThemeImage.image(
            CombatDenSlots.streakIcon,
            fallback: ApiImage.asset('streak_icon.png'),
          ),
          width: size,
          height: size,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

class _StatsContent extends StatelessWidget {
  const _StatsContent({required this.stats});

  final MockStreakStats stats;

  @override
  Widget build(BuildContext context) {
    final subtitleDelay = CelebrationTimings.countUpDuration;
    final stripDelay = subtitleDelay + CelebrationTimings.revealStagger;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: DesignConstants.spacingLarge,
      children: [
        _MainStatement(weekCount: stats.weekCount),
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
  const _MainStatement({required this.weekCount});

  final int weekCount;

  @override
  Widget build(BuildContext context) {
    return StaggeredReveal(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CountUpText(
            target: weekCount,
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
