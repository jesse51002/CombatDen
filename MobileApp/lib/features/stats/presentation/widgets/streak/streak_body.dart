import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:mobile_app/core/app_slots.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/stats/data/mock_stats.dart';
import 'package:mobile_app/features/stats/presentation/widgets/streak/streak_week_strip.dart';
import 'package:mobile_app/shared/widgets/animation/celebration_timings.dart';
import 'package:mobile_app/shared/widgets/animation/count_up_text.dart';
import 'package:mobile_app/shared/widgets/animation/staggered_reveal.dart';
import 'package:mobile_app/shared/widgets/api_image.dart';
import 'package:mobile_app/shared/widgets/branded_image.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_controller.dart';

// Per-screen layout/timing math, file-scoped per CLAUDE.md's _k carve-out.
const Duration _kBoltEntrance = Duration(milliseconds: 420);
const Duration _kBoltHold = Duration(milliseconds: 600);
const Duration _kBoltFade = Duration(milliseconds: 320);
const Duration _kLottieFadeOut = Duration(milliseconds: 240);
const double _kBoltSize = 240;
const double _kLottieSize = 320;
const double _kBoltStartScale = 0.5;
// Fraction of the Lottie's runtime at which the static icon starts entering
// (so the icon emerges *out of* the lightning strike, not after it).
const double _kIconTriggerProgress = 0.75;
const String _kLottieAsset = 'assets/animations/lightning_neon.json';

/// Layered celebration. The Lottie lightning strike plays in brand color;
/// halfway through, the 3D bolt icon enters with a bold scale + fade pop
/// *over* the still-playing strike. When the Lottie completes it fades out,
/// leaving the icon at full opacity. The icon then holds, fades, and the
/// week-count + "week streak" + small subtitle + week strip cascade in as
/// one centered focal block.
class StreakBody extends StatefulWidget {
  const StreakBody({super.key, required this.stats, this.controller});

  final MockStreakStats stats;
  final PostClassController? controller;

  @override
  State<StreakBody> createState() => _StreakBodyState();
}

class _StreakBodyState extends State<StreakBody> with TickerProviderStateMixin {
  late final AnimationController _lottieCtrl = AnimationController(vsync: this);
  late final AnimationController _entranceCtrl = AnimationController(
    vsync: this,
    duration: _kBoltEntrance,
  );
  late final AnimationController _exitCtrl = AnimationController(
    vsync: this,
    duration: _kBoltFade,
  );
  late final AnimationController _lottieFadeCtrl = AnimationController(
    vsync: this,
    duration: _kLottieFadeOut,
  );

  bool _iconEntered = false;
  bool _showStats = false;

  @override
  void initState() {
    super.initState();
    _lottieCtrl
      ..addListener(_onLottieTick)
      ..addStatusListener(_onLottieStatus);
    widget.controller?.registerSkipHandler(_skipToFinal);
  }

  void _skipToFinal() {
    if (_showStats) return;
    _lottieCtrl.stop();
    _entranceCtrl.stop();
    _exitCtrl.stop();
    _lottieFadeCtrl.stop();
    setState(() => _showStats = true);
    widget.controller?.markDone();
  }

  void _onLottieTick() {
    if (_iconEntered) return;
    if (_lottieCtrl.value < _kIconTriggerProgress) return;
    setState(() => _iconEntered = true);
    _entranceCtrl.forward();
  }

  void _onLottieStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    _lottieFadeCtrl.forward();
    Future.delayed(_kBoltHold, () {
      if (!mounted) return;
      _exitCtrl.forward().whenComplete(() {
        if (!mounted) return;
        setState(() => _showStats = true);
        widget.controller?.markDone();
      });
    });
  }

  @override
  void dispose() {
    widget.controller?.clearSkipHandler();
    _lottieCtrl
      ..removeListener(_onLottieTick)
      ..removeStatusListener(_onLottieStatus)
      ..dispose();
    _entranceCtrl.dispose();
    _exitCtrl.dispose();
    _lottieFadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showStats) {
      return _StatsContent(stats: widget.stats);
    }
    return Stack(
      alignment: Alignment.center,
      children: [
        if (_iconEntered)
          _IconHero(entranceCtrl: _entranceCtrl, exitCtrl: _exitCtrl),
        FadeTransition(
          opacity: ReverseAnimation(_lottieFadeCtrl),
          child: IgnorePointer(child: _LottieIntro(controller: _lottieCtrl)),
        ),
      ],
    );
  }
}

class _LottieIntro extends StatelessWidget {
  const _LottieIntro({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    final brand = DesignConstants.primaryColor;
    return SizedBox(
      width: _kLottieSize,
      height: _kLottieSize,
      child: Lottie.asset(
        _kLottieAsset,
        controller: controller,
        fit: BoxFit.contain,
        onLoaded: (composition) {
          controller
            ..duration = composition.duration
            ..forward();
        },
        delegates: LottieDelegates(
          values: [
            ValueDelegate.color(const ['**'], value: brand),
            ValueDelegate.strokeColor(const ['**'], value: brand),
          ],
        ),
      ),
    );
  }
}

class _IconHero extends StatelessWidget {
  const _IconHero({required this.entranceCtrl, required this.exitCtrl});

  final AnimationController entranceCtrl;
  final AnimationController exitCtrl;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([entranceCtrl, exitCtrl]),
      builder: (context, _) {
        final inT = Curves.easeOutQuart.transform(entranceCtrl.value);
        final outT = Curves.easeOutQuart.transform(exitCtrl.value);
        final opacity = inT * (1.0 - outT);
        final scale = _kBoltStartScale + (1.0 - _kBoltStartScale) * inT;
        return Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: scale,
            child: BrandedImage(
              slot: CombatDenSlots.streakIcon,
              fallback: ApiImage.asset('streak_icon.png'),
              width: _kBoltSize,
              height: _kBoltSize,
              fit: BoxFit.contain,
            ),
          ),
        );
      },
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
