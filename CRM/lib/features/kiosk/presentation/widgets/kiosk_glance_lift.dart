import 'package:flutter/material.dart';

import 'package:crm/features/kiosk/presentation/kiosk_reveal_timings.dart';

/// The confirmation copy that is actually PAINTED while it is in flight. Two
/// copies exist during the move, so a test has to name this one.
const Key kKioskGlanceTravellingConfirmation =
    Key('kiosk-glance-travelling-confirmation');

/// The glance's opening move: [confirmation] arrives CENTRED on the stage,
/// alone, holds for [KioskRevealTimings.centredHold], then travels UP into its
/// slot at the top of [rest]. One element moving, not two swapping (founder
/// ruling) — a fade-out here and a fade-in there reads as a cut.
///
/// The layout never moves: [rest] is laid out in full from frame one,
/// invisible but occupying its final pixels, so later beats can't reflow
/// anything and Done never shifts under the member's finger. The travel is a
/// paint-time alignment inside a [Stack] the settled column sizes, so centre
/// and top are exact by construction. Its cost is a second copy in flight: the
/// slot copy sits at zero opacity (which also drops it from semantics) and the
/// flying copy ignores pointers, so Done keeps working throughout.
///
/// Under reduced motion there is no hold, no travel and no second copy.
class KioskGlanceLift extends StatelessWidget {
  /// The one-line check-in confirmation. Its own entrance runs while centred.
  final Widget confirmation;

  /// Everything below the confirmation — the streak/rewards row and the
  /// glance footer. Always laid out, from the first frame.
  final Widget rest;

  /// The gap between the confirmation's slot and [rest].
  final double spacing;

  const KioskGlanceLift({
    super.key,
    required this.confirmation,
    required this.rest,
    required this.spacing,
  });

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return _SettledGlance(
        confirmation: confirmation,
        rest: rest,
        spacing: spacing,
      );
    }
    return _LiftingGlance(
      confirmation: confirmation,
      rest: rest,
      spacing: spacing,
    );
  }
}

/// The finished layout — the confirmation in its slot, everything else under
/// it. Laid out from frame one (invisibly, where [hideConfirmation] applies),
/// so it also reserves the space the whole choreography needs.
class _SettledGlance extends StatelessWidget {
  final Widget confirmation;
  final Widget rest;
  final double spacing;

  /// Holds the confirmation's slot at zero opacity while the travelling copy
  /// is on screen. The slot still lays out — that is the point.
  final bool hideConfirmation;

  const _SettledGlance({
    required this.confirmation,
    required this.rest,
    required this.spacing,
    this.hideConfirmation = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: spacing,
      children: [
        Opacity(opacity: hideConfirmation ? 0 : 1, child: confirmation),
        rest,
      ],
    );
  }
}

/// Drives the hold-then-travel with ONE controller: a single run spanning
/// hold + lift, with an [Interval] pinning the value at 0 through the hold. A
/// separate timer for the hold could drift out of step with the travel.
class _LiftingGlance extends StatefulWidget {
  final Widget confirmation;
  final Widget rest;
  final double spacing;

  const _LiftingGlance({
    required this.confirmation,
    required this.rest,
    required this.spacing,
  });

  @override
  State<_LiftingGlance> createState() => _LiftingGlanceState();
}

class _LiftingGlanceState extends State<_LiftingGlance>
    with SingleTickerProviderStateMixin {
  /// Hold + travel as one pass. Not `const` because `Duration`'s `+` isn't a
  /// const expression, and the beat sheet stays the only source of truth.
  static final Duration _span =
      KioskRevealTimings.centredHold + KioskRevealTimings.lift;

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: _span,
  );

  late final Animation<double> _travel = CurvedAnimation(
    parent: _ctrl,
    curve: Interval(
      KioskRevealTimings.centredHold.inMilliseconds / _span.inMilliseconds,
      1,
      curve: Curves.easeOutQuart,
    ),
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
      animation: _travel,
      builder: (context, _) {
        final t = _travel.value;
        final landed = t >= 1;
        return Stack(
          children: [
            // The sizing child: it defines the stack's box, which is what
            // makes "centre" and "top" below mean what they say.
            _SettledGlance(
              confirmation: widget.confirmation,
              rest: widget.rest,
              spacing: widget.spacing,
              hideConfirmation: !landed,
            ),
            if (!landed)
              Positioned.fill(
                child: IgnorePointer(
                  child: Align(
                    alignment: Alignment.lerp(
                      Alignment.center,
                      Alignment.topCenter,
                      t,
                    )!,
                    child: KeyedSubtree(
                      key: kKioskGlanceTravellingConfirmation,
                      child: widget.confirmation,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
