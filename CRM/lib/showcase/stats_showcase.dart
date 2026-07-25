import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:crm/showcase/showcase_assets.dart';
import 'package:crm/showcase/showcase_slots.dart';
import 'package:crm/showcase/showcase_tokens.dart';
import 'package:crm/shared/widgets/animation/count_up_text.dart';
import 'package:crm/showcase/support/showcase_scaffold.dart';
import 'package:crm/shared/widgets/animation/staggered_reveal.dart';
import 'package:crm/showcase/support/streak_week_strip.dart';
import 'package:theme_flutter/theme/animation/celebration_timings.dart';
import 'package:theme_flutter/theme/theme_image.dart';

// Per-screen layout/timing math (clone of MobileApp's streak_body _k consts).
const Duration _kDelay = Duration(milliseconds: 500);
// The mini-icon ring expands then immediately collapses — a quick out-and-back
// intro pulse before the big icon pop.
const Duration _kRingGrow = Duration(milliseconds: 600);
const Duration _kRingCollapse = Duration(milliseconds: 500);
// After the ring collapses, the big streak icon pops up, holds ~1s, then
// fades out into the stats cascade.
const Duration _kIconPop = Duration(milliseconds: 400);
const Duration _kIconHold = Duration(milliseconds: 800);
const Duration _kIconExit = Duration(milliseconds: 250);
const int _kOrbitCount = 8;
const double _kSpinTurns = 1.6;
const double _kOrbitSize = 30;
const double _kIconSize = 120;
const double _kReferenceExtent = 280;
const double _kEdgePad = 28;

// How long the stats statement holds before the orbit replays.
const Duration _kStatsHold = Duration(milliseconds: 2600);

// Dummy data — clone of MobileApp's `mockStreakStats`.
const int _kWeekCount = 3;
const String _kSubtitle = 'Completed your 2nd class this week';
const List<ShowcaseStreakDay> _kWeekDays = [
  ShowcaseStreakDay(label: 'S', completed: false),
  ShowcaseStreakDay(label: 'M', completed: true),
  ShowcaseStreakDay(label: 'T', completed: false),
  ShowcaseStreakDay(label: 'W', completed: false),
  ShowcaseStreakDay(label: 'T', completed: true),
  ShowcaseStreakDay(label: 'F', completed: false),
  ShowcaseStreakDay(label: 'S', completed: false),
];

/// Exact visual clone of the member app's post-class **streak celebration**
/// (`StreakScreen` / `StreakBody`): the streak icon pops in while a ring of
/// smaller streak icons expands + spins around it, then collapses; afterwards
/// the week count + "week streak" + subtitle + week strip cascade in. Loops.
class StatsShowcase extends StatefulWidget {
  const StatsShowcase({super.key, this.loop = true, this.onCycleComplete});

  final bool loop;
  final VoidCallback? onCycleComplete;

  @override
  State<StatsShowcase> createState() => _StatsShowcaseState();
}

class _StatsShowcaseState extends State<StatsShowcase> {
  bool _showStats = false;
  int _cycle = 0; // re-keying the orbit rebuilds + restarts it
  Timer? _hold;

  void _toStats() {
    if (!mounted || _showStats) return;
    setState(() => _showStats = true);
    _hold = Timer(_kStatsHold, _restart);
  }

  void _restart() {
    if (!mounted) return;
    widget.onCycleComplete?.call();
    if (!widget.loop) return;
    setState(() {
      _showStats = false;
      _cycle++;
    });
  }

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShowcaseScaffold(
      child: _showStats
          ? const Padding(
              padding: EdgeInsets.symmetric(
                vertical: ShowcaseTokens.spacingBig,
              ),
              child: Center(child: _StatsContent()),
            )
          : SizedBox.expand(
              child: _StreakOrbit(key: ValueKey(_cycle), onComplete: _toStats),
            ),
    );
  }
}

/// The intro animation: a single controller drives the sequence —
/// 1. **Delay**: a short beat of empty space before anything appears.
/// 2. **Ring**: a ring of small streak icons expands outward then collapses
///    back to center — spinning throughout. No big icon yet.
/// 3. **Icon**: once the ring is gone, the big streak icon pops up (overshoot
///    scale), holds ~1s, then fades out as the stats cascade takes over.
class _StreakOrbit extends StatefulWidget {
  const _StreakOrbit({super.key, required this.onComplete});

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
      duration: _kDelay +
          _kRingGrow +
          _kRingCollapse +
          _kIconPop +
          _kIconHold +
          _kIconExit,
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
        final orbitSize = _kOrbitSize * renderScale;
        final iconSize = _kIconSize * renderScale;
        final maxRadius = smallerExtent / 2 - _kEdgePad - orbitSize / 2;

        return AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final t = _ctrl.value;
            final total = _ctrl.duration!.inMilliseconds.toDouble();
            // Phase boundaries as fractions of the controller timeline.
            final d = _kDelay.inMilliseconds;
            final g = _kRingGrow.inMilliseconds;
            final c = _kRingCollapse.inMilliseconds;
            final p = _kIconPop.inMilliseconds;
            final ih = _kIconHold.inMilliseconds;
            final delayEnd = d / total;
            final ringGrowEnd = (d + g) / total;
            final ringEnd = (d + g + c) / total;
            final iconPopEnd = (d + g + c + p) / total;
            final iconHoldEnd = (d + g + c + p + ih) / total;

            // Mini-icon ring: expand → collapse to center (no hold).
            final growT =
                ((t - delayEnd) / (ringGrowEnd - delayEnd)).clamp(0.0, 1.0);
            final ringCollapseT =
                ((t - ringGrowEnd) / (ringEnd - ringGrowEnd)).clamp(0.0, 1.0);
            final expandE = Curves.easeOutQuart.transform(growT);
            final ringCollapseE = Curves.easeInQuart.transform(ringCollapseT);

            // 0 → 1 (grow), 1 (hold), 1 → 0 (collapse).
            final radiusFactor = expandE * (1 - ringCollapseE);
            final radius = maxRadius * radiusFactor;
            final spin = t * 2 * math.pi * _kSpinTurns;

            // Big center icon: pops up only after the ring has collapsed,
            // holds ~1s, then fades out into the stats cascade.
            final iconPopT =
                ((t - ringEnd) / (iconPopEnd - ringEnd)).clamp(0.0, 1.0);
            final iconExitT =
                ((t - iconHoldEnd) / (1 - iconHoldEnd)).clamp(0.0, 1.0);
            final iconExitE = Curves.easeInQuart.transform(iconExitT);
            final iconScale =
                Curves.easeOutBack.transform(iconPopT) * (1 - 0.3 * iconExitE);
            final iconOpacity =
                Curves.easeOut.transform(iconPopT) * (1 - iconExitE);

            return Stack(
              alignment: Alignment.center,
              children: [
                for (var i = 0; i < _kOrbitCount; i++)
                  _orbitIcon(i, spin, radius, radiusFactor, orbitSize),
                _icon(iconScale, iconOpacity, iconSize),
              ],
            );
          },
        );
      },
    );
  }

  Widget _orbitIcon(
    int i,
    double spin,
    double radius,
    double opacity,
    double size,
  ) {
    final theta = spin + i * 2 * math.pi / _kOrbitCount;
    return Transform.translate(
      offset: Offset(math.cos(theta) * radius, math.sin(theta) * radius),
      child: Opacity(opacity: opacity.clamp(0.0, 1.0), child: _image(size)),
    );
  }

  Widget _icon(double scale, double opacity, double size) {
    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: Transform.scale(scale: scale, child: _image(size)),
    );
  }

  Widget _image(double size) {
    return Image(
      image: ThemeImage.image(
        ShowcaseSlots.streakIcon,
        fallback: ShowcaseAsset.image('streak_icon.png'),
      ),
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}

class _StatsContent extends StatelessWidget {
  const _StatsContent();

  @override
  Widget build(BuildContext context) {
    final subtitleDelay = CelebrationTimings.countUpDuration;
    final stripDelay = subtitleDelay + CelebrationTimings.revealStagger;

    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: ShowcaseTokens.spacingLarge,
      children: [
        StaggeredReveal(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CountUpText(
                target: _kWeekCount,
                style: ShowcaseTokens.big1,
                textAlign: TextAlign.center,
              ),
              Text(
                'week streak',
                textAlign: TextAlign.center,
                style: ShowcaseTokens.big2,
              ),
            ],
          ),
        ),
        StaggeredReveal(
          delay: subtitleDelay,
          child: Text(
            _kSubtitle,
            textAlign: TextAlign.center,
            style: ShowcaseTokens.p.copyWith(color: ShowcaseTokens.text2nd),
          ),
        ),
        StreakWeekStrip(days: _kWeekDays, baseDelay: stripDelay),
      ],
    );
  }
}
