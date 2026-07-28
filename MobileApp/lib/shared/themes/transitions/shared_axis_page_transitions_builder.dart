import 'package:flutter/material.dart';

import 'package:mobile_app/shared/themes/transitions/transition_motion.dart';

/// `TransitionStyle.sharedAxis` — a paired slide plus fade along the
/// navigation axis (Material's shared-axis pattern, X axis).
///
/// Both halves move: the arriving screen travels in from the leading
/// edge while the leaving one carries on in the same direction. The
/// pairing is what makes the axis legible — one screen moving alone
/// reads as an overlay, two screens moving together read as a step
/// along a line.
///
/// One builder covers both halves. A route's own `buildTransitions`
/// receives `animation` while it is arriving and `secondaryAnimation`
/// while something is arriving on top of it, so the outer pair below is
/// inert (offset zero, opacity one) for the arriving screen and the
/// inner pair is inert for the leaving one.
class SharedAxisPageTransitionsBuilder extends PageTransitionsBuilder {
  const SharedAxisPageTransitionsBuilder();

  static const Duration duration = Duration(milliseconds: 320);

  /// Travel, as a fraction of the screen's width. Far enough to read as
  /// a direction, short enough that the two halves stay related.
  static const double travel = 0.25;

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
          begin: const Offset(travel, 0),
          end: Offset.zero,
        ).chain(CurveTween(curve: TransitionMotion.travel)),
      ),
      child: FadeTransition(
        opacity: animation.drive(CurveTween(curve: TransitionMotion.fade)),
        child: child,
      ),
    );

    return SlideTransition(
      position: secondaryAnimation.drive(
        Tween<Offset>(
          begin: Offset.zero,
          end: const Offset(-travel, 0),
        ).chain(CurveTween(curve: TransitionMotion.travel)),
      ),
      child: FadeTransition(
        opacity: secondaryAnimation.drive(
          Tween<double>(
            begin: 1,
            end: 0,
          ).chain(CurveTween(curve: TransitionMotion.fade)),
        ),
        child: arriving,
      ),
    );
  }
}
