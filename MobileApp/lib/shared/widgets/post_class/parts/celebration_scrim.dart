import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';

/// The height `fullBleed` keeps clear beneath its stage: the action's own
/// rendered height plus the gap above it and the inset below it. Pure
/// layout arithmetic with no `DesignConstants` equivalent (a button's
/// intrinsic height is not a design token), so it lives here as a `_k`
/// constant rather than as a literal at the call site.
const double kCelebrationCtaZone = 48 + DesignConstants.spacingBig * 2;

/// The scrim `fullBleed` lays under its floating action.
///
/// Rises out of the canvas rather than glowing: the fill is
/// `backgroundColor`, never `primaryColor`. Orange is reserved for
/// agency, and a second bright wash here would spend celebration the
/// post-class cards have already earned once.
///
/// It overlaps the stage by exactly one `spacingBig`, at the very top of
/// the gradient where alpha is still near zero, so the captions two of
/// the cards pin to their own bottom edge stay readable.
class CelebrationScrim extends StatelessWidget {
  const CelebrationScrim({super.key});

  static const double _kHeight =
      kCelebrationCtaZone + DesignConstants.spacingBig;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        height: _kHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                DesignConstants.backgroundColor.withValues(alpha: 0),
                DesignConstants.backgroundColor,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
