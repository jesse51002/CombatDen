import 'package:flutter/material.dart';

/// Lays [child] out at the FULL width it is given, then scales the whole thing
/// down uniformly if it comes out taller than the box. Never scales up.
///
/// This is the alternative to a scrollbar on a surface that must not scroll —
/// the kiosk, where a member never discovers content below a fold. When the
/// content fits (the normal case) nothing happens at all; when a short fold
/// leaves it a few pixels short, the composition shrinks **as a set**, so the
/// type ramp, the artwork and the spacing keep their exact proportions to each
/// other instead of one element being singled out and squashed.
///
/// It is deliberately width-first: a bare `FittedBox` lays its child out
/// completely unbounded, which lets text run onto one enormous line before the
/// scale is computed. Pinning the width to the box first means the child wraps
/// exactly as designed and only the vertical shortfall drives the scale.
///
/// With an unbounded box there is nothing to fit against, so the child is
/// returned untouched.
class ShrinkToFit extends StatelessWidget {
  final Widget child;

  const ShrinkToFit({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedHeight || !constraints.hasBoundedWidth) {
          return child;
        }
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(width: constraints.maxWidth, child: child),
        );
      },
    );
  }
}
