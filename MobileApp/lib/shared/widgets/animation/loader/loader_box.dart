import 'package:flutter/rendering.dart';

/// The box every loader value draws inside.
///
/// It is the SHIPPED DOTS' geometry, and every value inherits it: a
/// motion format may change timing and entrance, never how much room the
/// waiting state takes on the screen that is waiting. Whichever value a
/// tenant picks, the loader occupies the same rectangle.
class LoaderBox {
  const LoaderBox({
    required this.size,
    required this.markExtent,
    required this.liftSpan,
  });

  /// The rectangle the loader fills.
  final Size size;

  /// A mark's nominal extent: the shipped dot's diameter.
  final double markExtent;

  /// How far a `LoaderMark.lift` of 1 raises a mark.
  final double liftSpan;
}
