import 'package:flutter/material.dart';

import 'package:crm/features/kiosk/presentation/kiosk_reveal_timings.dart';

/// The key on the confirmation copy that is actually PAINTED while the
/// confirmation is in flight. Two copies exist during the move (see
/// [KioskGlanceLift]) and only this one is on screen, so a test that asks
/// "where is the confirmation right now?" has to name it.
const Key kKioskGlanceTravellingConfirmation =
    Key('kiosk-glance-travelling-confirmation');

/// The glance's opening move: [confirmation] arrives CENTRED on the stage,
/// alone, holds there for [KioskRevealTimings.centredHold], then travels UP
/// into its slot at the top of [rest].
///
/// **It is one element moving, not two elements swapping.** A fade-out here
/// and a fade-in there would read as a cut; the founder asked for the
/// confirmation itself to go up, so the same widget is carried from the centre
/// of the stage to the top on [Curves.easeOutQuart] — the app's motion law,
/// the curve `StaggeredReveal` and `ScaleReveal` already ride (ease-out, no
/// bounce), stretched to [KioskRevealTimings.lift] so the travel is unhurried
/// enough to follow.
///
/// **The layout never moves.** [rest] — the two panels and the glance footer —
/// is laid out in full from the very first frame, invisible but occupying
/// every pixel it will occupy at the end, so the streak and rewards appearing
/// later cannot reflow anything and the footer's Done button never shifts
/// under the member's finger. The confirmation's travel is a paint-time
/// alignment, so it moves nothing either.
///
/// **How the centring is computed:** the travelling copy is a [Positioned.fill]
/// child of a [Stack] the settled column sizes, so [Alignment.center] is
/// literally the centre of the finished glance and [Alignment.topCenter] is
/// literally the confirmation's own slot — no measurement, no magic distance,
/// and the two ends of the move are exact by construction. The cost is that
/// the confirmation is built twice while it travels: once in the column, held
/// at zero opacity purely to reserve its slot, and once in flight. The hidden
/// copy is dropped from semantics by its zero opacity (so a screen reader hears
/// the confirmation exactly once), the flying copy ignores pointers (so Done
/// and the glance's tap-to-open-the-app gesture keep working throughout), and
/// the moment the travel lands the flying copy is removed and the slot copy
/// becomes visible in the same position — an invisible handover.
///
/// Under reduced motion there is no hold, no travel and no second copy: the
/// settled column is returned directly, the same precedent `KioskReveal` and
/// `KioskAppShowcase` set.
class KioskGlanceLift extends StatelessWidget {
  /// The one-line check-in confirmation. Whatever entrance it carries of its
  /// own (its [KioskReveal] fade, the check disc's pop) runs while it is
  /// centred.
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
/// it. This is what the glance looks like once the move has landed, and it is
/// laid out (invisibly, where [hideConfirmation] applies) from frame one, so
/// it is also what reserves the space the whole choreography needs.
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
/// [KioskRevealTimings.centredHold] + [KioskRevealTimings.lift], with an
/// [Interval] pinning the value at 0 through the hold. A second timer for the
/// hold could drift out of step with the travel; one clock cannot.
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
  /// Hold + travel, run as one pass. Not `const` because `Duration`'s `+` is
  /// not a const expression — the beat sheet stays the only source of truth.
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
