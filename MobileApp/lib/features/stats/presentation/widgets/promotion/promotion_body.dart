import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/profile/data/models/member_promotion.dart';
import 'package:mobile_app/features/stats/presentation/widgets/promotion/promotion_settled_block.dart';
import 'package:mobile_app/shared/widgets/animation/celebration_timings.dart';
import 'package:mobile_app/shared/widgets/animation/sparkle_burst.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_controller.dart';
import 'package:mobile_app/shared/widgets/rank/rank_belt_image.dart';

// Per-screen layout/timing math, file-scoped per CLAUDE.md's _k carve-out.
const Duration _kEnter = Duration(milliseconds: 420); // = RankBody._kEntrance
const Duration _kHold = Duration(milliseconds: 560);
const Duration _kSwap = Duration(milliseconds: 360);
const Duration _kSettle = Duration(milliseconds: 700); // = RankBody._kShrink
const double _kHeroBelt = 280; // = RankBody._kBigBelt
const double _kBeltStartScale = 0.5; // = RankBody._kBeltStartScale
const double _kSwell = 0.06;
const double _kNameExitRise = 12; // = StaggeredReveal's default offset
const String _kBeltAsset = 'stat_rank_belt.png';

const String _kPromotedEyebrow = "YOU'VE BEEN PROMOTED";
const String _kFirstRankEyebrow = 'YOUR FIRST RANK';

/// Belt promotion: the belt is ONE object whose identity changes.
///
/// It extends `RankBody`'s belt-motion sentence rather than writing a second
/// one — a 280pt centred hero that physically interpolates `left/top/width/
/// height` into a `GlobalKey`-measured slot while the surrounding block
/// cross-fades in around it. The belt is never swapped for another widget: no
/// flip, no spin, no card-turn. Nothing in this app rotates, and a belt is not
/// a playing card.
///
/// The whole design follows from one problem: **a cross-dissolve of two belts
/// can be invisible.** A stripe promotion may snapshot the same art on both
/// sides, a legacy row carries no art at all, and two adjacent stripe images
/// differ by a thread of tape. So the swap beat fires FOUR simultaneous
/// signals, any one of which carries the moment alone — the dissolve, the old
/// name exiting upward, the sparkle burst, and the belt's swell. Colour is
/// never a signal here, which is what makes it safe under white-labelling.
///
/// Beats (main case, 2,660ms): enter 420 / hold 560 / swap 360 / admire 620
/// (the sparkle window, by definition) / settle 700. A FIRST ASSIGNMENT drops
/// the hold and the swap — there is nothing to animate from, so it renders an
/// arrival: enter / admire / settle, 1,740ms, sparkles from `t = 0`.
///
/// **Nothing here is a self-driving child animation.** Every value —
/// dissolve, swell, name exit, belt flight, block cross-fade — is derived from
/// the one controller, so a skip (`_ctrl.value = 1`) paints the final frame in
/// full. A `ScaleReveal` / `CountUpText` child runs its own controller off a
/// timer that no jump can fast-forward. The only self-driven thing is
/// `SparkleBurst`, and it is SUPPRESSED on a skip rather than skipped.
class PromotionBody extends StatefulWidget {
  const PromotionBody({super.key, required this.promotion, this.controller});

  final MemberPromotion promotion;
  final PostClassController? controller;

  @override
  State<PromotionBody> createState() => _PromotionBodyState();
}

class _PromotionBodyState extends State<PromotionBody>
    with SingleTickerProviderStateMixin {
  /// Fixed for the widget's lifetime, so no conditional child in the `Stack`
  /// ever appears or disappears mid-animation.
  late final bool _firstAssignment = widget.promotion.isFirstAssignment;

  late final Duration _total = _firstAssignment
      ? _kEnter + CelebrationTimings.sparkleWindow + _kSettle
      : _kEnter + _kHold + _kSwap + CelebrationTimings.sparkleWindow + _kSettle;

  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: _total);

  /// The leaf the member came FROM, or null when there is none. One composed
  /// display string — never split on the `·`.
  late final String? _oldName = _blankToNull(widget.promotion.oldRankName);

  final GlobalKey _stackKey = GlobalKey();
  final GlobalKey _slotKey = GlobalKey();

  Rect? _slotRect;
  bool _skipped = false;

  static String? _blankToNull(String? raw) {
    final v = raw?.trim() ?? '';
    return v.isEmpty ? null : v;
  }

  @override
  void initState() {
    super.initState();
    _ctrl
      ..addStatusListener(_onStatus)
      ..forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureSlot());
    widget.controller?.registerSkipHandler(_skipToFinal);
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      widget.controller?.markDone();
    }
  }

  void _measureSlot() {
    if (!mounted || _slotRect != null) return;
    final slotBox = _slotKey.currentContext?.findRenderObject() as RenderBox?;
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (slotBox == null || stackBox == null) return;
    if (!slotBox.hasSize || !stackBox.hasSize) return;
    final pos = slotBox.localToGlobal(Offset.zero, ancestor: stackBox);
    setState(() => _slotRect = pos & slotBox.size);
  }

  void _skipToFinal() {
    if (!mounted) return;
    // Set BEFORE the jump so the very next build cannot mount `SparkleBurst`
    // on the skip frame — a scatter that BEGINS animating after a skip is the
    // opposite of what was asked for.
    setState(() => _skipped = true);
    _ctrl.value = 1.0;
    widget.controller?.markDone();
  }

  @override
  void dispose() {
    widget.controller?.clearSkipHandler();
    _ctrl
      ..removeStatusListener(_onStatus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // LayoutBuilder lifted above the Stack so the belt's "centred + big" rect
    // is computable in stack-local coordinates and can be emitted as a
    // `Positioned` DIRECT child of the Stack.
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackW = constraints.maxWidth;
        final stackH = constraints.maxHeight;
        return AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            // Phase boundaries derived from the Duration constants, never
            // typed as fractions.
            final total = _total.inMilliseconds.toDouble();
            final enterEnd = _kEnter.inMilliseconds / total;
            final swapStart =
                _firstAssignment ? 0.0 : (_kEnter + _kHold).inMilliseconds / total;
            final swapEnd = _firstAssignment
                ? 0.0
                : (_kEnter + _kHold + _kSwap).inMilliseconds / total;
            final settleStart = (_total - _kSettle).inMilliseconds / total;

            final t = _ctrl.value;
            final enterE =
                Curves.easeOutQuart.transform((t / enterEnd).clamp(0.0, 1.0));
            // A first assignment has no swap: the new belt is simply present.
            final swapT = _firstAssignment
                ? 1.0
                : ((t - swapStart) / (swapEnd - swapStart)).clamp(0.0, 1.0);
            final settleE = Curves.easeOutQuart
                .transform(((t - settleStart) / (1 - settleStart)).clamp(0.0, 1.0));

            return Stack(
              key: _stackKey,
              fit: StackFit.expand,
              children: [
                // Behind the art, and always at this index so the burst's own
                // controller is never remounted by a shifting child list.
                Positioned.fill(
                  child: Center(
                    child: !_skipped && t >= swapStart
                        ? const SparkleBurst(size: _kHeroBelt)
                        : const SizedBox.shrink(),
                  ),
                ),
                Opacity(
                  opacity: settleE,
                  child: PromotionSettledBlock(
                    eyebrow:
                        _firstAssignment ? _kFirstRankEyebrow : _kPromotedEyebrow,
                    newRankName: widget.promotion.newRankName?.trim() ?? '',
                    fromLine: _oldName == null ? null : 'from $_oldName',
                    slotKey: _slotKey,
                  ),
                ),
                if (_oldName case final name?) _oldNameLabel(name, enterE, swapT),
                _animatedBelt(enterE, swapT, settleE, stackW, stackH),
              ],
            );
          },
        );
      },
    );
  }

  /// The belt the member is leaving, named under the hero and exiting UPWARD
  /// as it dissolves — the member moved up, and it is the same direction a
  /// `CountUpText` digit reel travels when a number increases. This is the
  /// signal that survives when the two belt images are identical.
  Widget _oldNameLabel(String name, double enterE, double swapT) {
    return Center(
      child: Transform.translate(
        offset: Offset(
          0,
          _kHeroBelt / 2 + DesignConstants.spacingBig - _kNameExitRise * swapT,
        ),
        child: Opacity(
          opacity: (enterE * (1 - swapT)).clamp(0.0, 1.0),
          child: Text(
            name,
            textAlign: TextAlign.center,
            style: DesignConstants.h2.copyWith(color: DesignConstants.text2nd),
          ),
        ),
      ),
    );
  }

  /// The two sides, co-located and cross-dissolving, sized and placed by the
  /// caller as ONE box. Each side resolves independently through the app's one
  /// belt ladder, so a null / failing side degrades to the themed belt without
  /// a branch here.
  Widget _beltPair(double swapT) {
    // Constant-power dissolve, NOT linear opacity: two images at `a` and
    // `1 - a` over a near-black canvas dip in luminance at the midpoint, and a
    // mid-dissolve dip on a dark screen reads as a flicker rather than a
    // morph. This is the one place a non-eased opacity curve is correct — two
    // co-located images have no arrival to decelerate into.
    final oldOpacity = math.sqrt(1 - swapT);
    final newOpacity = math.sqrt(swapT);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (!_firstAssignment)
          Opacity(
            opacity: oldOpacity,
            child: RankBeltImage(
              imageUrl: widget.promotion.oldImageUrl,
              asset: _kBeltAsset,
            ),
          ),
        Opacity(
          opacity: newOpacity,
          child: RankBeltImage(
            imageUrl: widget.promotion.newImageUrl,
            asset: _kBeltAsset,
          ),
        ),
      ],
    );
  }

  Widget _animatedBelt(
    double enterE,
    double swapT,
    double settleE,
    double stackW,
    double stackH,
  ) {
    final pair = _beltPair(swapT);
    // Symmetric swell that ends exactly where it started — deliberately NOT a
    // bounce or elastic curve (those overshoot a target and oscillate around
    // it, which the app bans). It is `_PulseOnLand`'s idea made symmetric,
    // because there is no landing to punctuate, only a change.
    final swell = 1 + _kSwell * math.sin(math.pi * swapT);

    // Enter / hold / swap / admire — or before the slot has been measured:
    // big and centred.
    if (settleE <= 0 || _slotRect == null) {
      final size = _kHeroBelt *
          (_kBeltStartScale + (1 - _kBeltStartScale) * enterE) *
          swell;
      return Center(
        child: Opacity(
          opacity: enterE,
          child: SizedBox(width: size, height: size, child: pair),
        ),
      );
    }

    // Settle: interpolate left/top/width/height from "big and centred" into
    // the measured slot. The belt stays a single rendered widget.
    final bigLeft = (stackW - _kHeroBelt) / 2;
    final bigTop = (stackH - _kHeroBelt) / 2;
    final rect = _slotRect!;
    return Positioned(
      left: bigLeft + (rect.left - bigLeft) * settleE,
      top: bigTop + (rect.top - bigTop) * settleE,
      width: _kHeroBelt + (rect.width - _kHeroBelt) * settleE,
      height: _kHeroBelt + (rect.height - _kHeroBelt) * settleE,
      child: pair,
    );
  }
}
