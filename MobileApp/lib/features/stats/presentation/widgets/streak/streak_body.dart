import 'package:flutter/material.dart';
import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/stats/data/mock_stats.dart';
import 'package:mobile_app/features/stats/presentation/widgets/streak/streak_week_strip.dart';
import 'package:mobile_app/shared/widgets/animation/celebration_timings.dart';
import 'package:mobile_app/shared/widgets/animation/count_up_text.dart';
import 'package:mobile_app/shared/widgets/animation/staggered_reveal.dart';
import 'package:mobile_app/shared/widgets/api_image.dart';
import 'package:mobile_app/customization/widgets/branded_image.dart';
import 'package:mobile_app/customization/widgets/reveal_lottie.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_controller.dart';

// Per-screen layout/timing math, file-scoped per CLAUDE.md's _k carve-out.
const double _kLottieSize = 320;
// Fraction of the strike's runtime at which the streak icon pops out (so it
// emerges *out of* the lightning, not after it). Used on the bundled
// fallback; a real reveal preset's insertion_point overrides it.
const double _kRevealAt = 0.75;
const String _kLottieAsset = 'assets/animations/lightning_neon.json';

/// Layered celebration. A `RevealLottie` plays the lightning strike (brand
/// recoloured) and pops the streak icon out of it partway through; when the
/// strike finishes, the week-count + "week streak" + subtitle + week strip
/// cascade in as one centered focal block.
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
    // RevealLottie plays the strike and pops the streak icon out of it; when
    // the strike finishes we cross into the stats cascade.
    return RevealLottie(
      slot: CombatDenSlots.streakCelebration,
      fallbackAsset: _kLottieAsset,
      width: _kLottieSize,
      height: _kLottieSize,
      revealProgress: _kRevealAt,
      onComplete: _toStats,
      revealedImage: BrandedImage(
        slot: CombatDenSlots.streakIcon,
        fallback: ApiImage.asset('streak_icon.png'),
        fit: BoxFit.contain,
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
