import 'dart:async';

import 'package:flutter/material.dart';

import 'package:customization_engine/showcase/showcase_assets.dart';
import 'package:customization_engine/showcase/showcase_slots.dart';
import 'package:customization_engine/showcase/showcase_tokens.dart';
import 'package:customization_engine/showcase/support/count_up_text.dart';
import 'package:customization_engine/showcase/support/showcase_scaffold.dart';
import 'package:customization_engine/showcase/support/staggered_reveal.dart';
import 'package:customization_engine/showcase/support/streak_week_strip.dart';
import 'package:customization_engine/theme/lottie/celebration_timings.dart';
import 'package:customization_engine/theme/lottie/theme_reveal_lottie.dart';
import 'package:customization_engine/theme/theme_image.dart';

// Per-screen layout/timing math (clone of MobileApp's streak_body _k consts).
const double _kLottieSize = 320;
const double _kRevealAt = 0.75;
const double _kRevealX = 0.2;
const double _kRevealY = 0.2;
const double _kRevealWidth = 0.6;
const double _kRevealHeight = 0.6;

// How long the stats statement holds before the strike replays.
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
/// (`StreakScreen` / `StreakBody`): a brand-recoloured lightning strike pops
/// the streak icon out of itself, then the week count + "week streak" +
/// subtitle + week strip cascade in. Loops.
class StatsShowcase extends StatefulWidget {
  const StatsShowcase({super.key, this.loop = true, this.onCycleComplete});

  final bool loop;
  final VoidCallback? onCycleComplete;

  @override
  State<StatsShowcase> createState() => _StatsShowcaseState();
}

class _StatsShowcaseState extends State<StatsShowcase> {
  bool _showStats = false;
  int _cycle = 0; // re-keying the strike rebuilds + restarts it
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
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: ShowcaseTokens.spacingBig,
        ),
        child: Center(child: _showStats ? const _StatsContent() : _strike()),
      ),
    );
  }

  Widget _strike() {
    return SizedBox(
      width: _kLottieSize,
      height: _kLottieSize,
      child: ThemeRevealLottie(
        key: ValueKey(_cycle),
        slot: ShowcaseSlots.streakCelebration,
        fallbackAsset: ShowcaseAsset.animation('lightning_neon.json'),
        fallbackRevealAt: _kRevealAt,
        fallbackX: _kRevealX,
        fallbackY: _kRevealY,
        fallbackWidth: _kRevealWidth,
        fallbackHeight: _kRevealHeight,
        onComplete: _toStats,
        revealedImage: Image(
          image: ThemeImage.image(
            ShowcaseSlots.streakIcon,
            fallback: ShowcaseAsset.image('streak_icon.png'),
          ),
          fit: BoxFit.contain,
        ),
      ),
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
