import 'package:flutter/material.dart';

/// `TransitionStyle.none` — an instant cut.
///
/// Zero duration and an untouched child: the arriving screen is simply
/// there on the next frame. This is the one authored value deliberately
/// under the legibility floor, because it is not an animation at all —
/// a tenant picking it is asking for no screen-to-screen motion, not
/// for a very fast one.
class InstantPageTransitionsBuilder extends PageTransitionsBuilder {
  const InstantPageTransitionsBuilder();

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}
