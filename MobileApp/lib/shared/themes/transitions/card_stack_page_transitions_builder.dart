import 'package:flutter/material.dart';

import 'package:mobile_app/shared/themes/transitions/transition_motion.dart';

/// `TransitionStyle.cardStack` — the arriving screen rises over the one
/// it covers, which recedes slightly behind it.
///
/// The two halves say different things: the rise says "this is new and
/// it is on top", the recede says "the thing you were on is still
/// there, one layer back". The recede is a scale only — no dim — so the
/// receding screen stays legible as itself rather than turning into a
/// grey plate.
///
/// The longest authored value, because it travels the furthest and asks
/// the eye to read two layers instead of one.
class CardStackPageTransitionsBuilder extends PageTransitionsBuilder {
  const CardStackPageTransitionsBuilder();

  static const Duration duration = Duration(milliseconds: 360);

  /// How far the arriving screen rises, as a fraction of its height.
  static const double rise = 0.18;

  /// The scale the covered screen settles back to while it is covered.
  static const double recede = 0.94;

  /// The arriving screen reaches full opacity early in its rise, so it
  /// reads as a solid card being moved rather than as a ghost. The
  /// interval starts at zero — a page transition answers a tap and may
  /// never hold still first.
  static const Interval _arrivalFade = Interval(
    0,
    0.35,
    curve: TransitionMotion.fade,
  );

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
    final arriving = SlideTransition(
      position: animation.drive(
        Tween<Offset>(
          begin: const Offset(0, rise),
          end: Offset.zero,
        ).chain(CurveTween(curve: TransitionMotion.travel)),
      ),
      child: FadeTransition(
        opacity: animation.drive(CurveTween(curve: _arrivalFade)),
        child: child,
      ),
    );

    return ScaleTransition(
      scale: secondaryAnimation.drive(
        Tween<double>(
          begin: 1,
          end: recede,
        ).chain(CurveTween(curve: TransitionMotion.travel)),
      ),
      child: arriving,
    );
  }
}
