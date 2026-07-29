import 'package:flutter/material.dart';

import 'package:mobile_app/shared/themes/transitions/transition_motion.dart';

/// `TransitionStyle.fade` — a cross-dissolve with no translation.
///
/// The arriving screen fades up over the one it replaces, which is
/// still painted underneath at full opacity for the whole transition.
/// That is deliberate: fading BOTH halves crosses through a moment
/// where neither is opaque and the scaffold colour washes through the
/// middle of the dissolve. Fading only the arriving half reads as the
/// same cross-fade with none of the wash, and it reverses correctly on
/// a pop for free — popping runs this same opacity backwards, so the
/// leaving screen dissolves off the one below it.
///
/// The longest of the three authored values relative to its travel
/// distance, because it has none: opacity is the only cue, and an
/// opacity-only change needs longer on screen to be read than a
/// movement does.
class FadePageTransitionsBuilder extends PageTransitionsBuilder {
  const FadePageTransitionsBuilder();

  static const Duration duration = Duration(milliseconds: 300);

  @override
  Duration get transitionDuration => duration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: animation.drive(
        CurveTween(curve: TransitionMotion.fade),
      ),
      child: child,
    );
  }
}
