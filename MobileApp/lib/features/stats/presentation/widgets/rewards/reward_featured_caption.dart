import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/stats/data/rewards_card_view.dart';

// Reserved caption slots — the `RewardCard._kCardTitleHeight` idiom, for the
// same reason: the auto-advance cross-fades between two children, and any
// per-slide height difference would shift the whole stack on every rotation.
// Name: one line of h1. Value: an h1 line + spacingSmall + the "Ready to
// redeem" row, which is the tallest branch (redeemable), so the shorter ones
// sit high and the slack falls below.
//
// They are FLOORS, not fixed heights: the app re-fonts per tenant
// (`ThemeFont` resolves a Google Font per gym), and a font with taller
// metrics than these would clip its own text under a hard `SizedBox`. A
// too-short floor degrades to a shift on advance; a too-short SizedBox
// degrades to unreadable text, which is worse.
const double _kCaptionNameHeight = 34;
const double _kCaptionValueHeight = 61;

/// The featured reward's name over its value, both height-reserved so the
/// stack is pixel-stable across every slide and every affordance.
///
/// The value line says what the member can DO, not just what the thing costs:
/// `800 pts` with a "Ready to redeem" line under it when they can have it, the
/// `120 / 2,200 points` progress sentence — `NextRankSection`'s
/// `'$done / $target classes'` form transposed to points — when they can't.
class RewardFeaturedCaption extends StatelessWidget {
  const RewardFeaturedCaption({
    super.key,
    required this.slide,
    required this.featuredIndex,
  });

  final RewardsCardSlide slide;

  /// Re-keys the pulse so each advance re-fires it.
  final int featuredIndex;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _kCaptionNameHeight),
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: 1,
            child: Text(
              slide.slide.name,
              textAlign: TextAlign.center,
              style: DesignConstants.h1,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _kCaptionValueHeight),
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: 1,
            child: _ValueBlock(slide: slide, featuredIndex: featuredIndex),
          ),
        ),
      ],
    );
  }
}

class _ValueBlock extends StatelessWidget {
  const _ValueBlock({required this.slide, required this.featuredIndex});

  final RewardsCardSlide slide;
  final int featuredIndex;

  @override
  Widget build(BuildContext context) {
    // A shortfall is not a celebration beat — pulsing it would celebrate the
    // gap — so the locked branch is the one that never pulses.
    if (slide.affordance == RewardAffordance.locked) {
      return Text(
        slide.valueLabel,
        textAlign: TextAlign.center,
        style: DesignConstants.h2Regular.copyWith(
          color: DesignConstants.text2nd,
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingSmall,
      children: [
        _PulsePoints(
          key: ValueKey('pts-$featuredIndex'),
          child: Text(
            slide.valueLabel,
            textAlign: TextAlign.center,
            style: DesignConstants.h1.copyWith(
              color: DesignConstants.primaryColor,
            ),
          ),
        ),
        if (slide.affordance == RewardAffordance.redeemable)
          const _ReadyLine(),
      ],
    );
  }
}

class _ReadyLine extends StatelessWidget {
  const _ReadyLine();

  @override
  Widget build(BuildContext context) {
    final accent = DesignConstants.accent;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingSmall,
      children: [
        Icon(
          Symbols.check_sharp,
          weight: DesignConstants.iconWeight,
          size: DesignConstants.iconSizeSm,
          color: accent,
        ),
        Text(
          'Ready to redeem',
          style: DesignConstants.h2.copyWith(color: accent),
        ),
      ],
    );
  }
}

/// One-shot scale-pulse (1.0 -> 1.06 -> 1.0) on first build. Each new
/// keyed instance re-fires it, so swapping the key on advance gives a
/// per-rotation pulse.
class _PulsePoints extends StatefulWidget {
  const _PulsePoints({super.key, required this.child});

  final Widget child;

  @override
  State<_PulsePoints> createState() => _PulsePointsState();
}

class _PulsePointsState extends State<_PulsePoints>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final v = _ctrl.value;
        // Bell curve: 0 -> 1 -> 0 across the duration.
        final bell = (v < 0.5 ? v * 2 : (1 - v) * 2);
        final eased = Curves.easeOutQuart.transform(bell);
        return Transform.scale(scale: 1.0 + 0.06 * eased, child: child);
      },
      child: widget.child,
    );
  }
}
