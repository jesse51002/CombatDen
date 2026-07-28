import 'package:flutter/rendering.dart';

/// Uncovers [fraction] of a box along its own LONG axis.
///
/// A wide element (a caption, a button, a card) sweeps horizontally from
/// the leading edge; a tall one sweeps top-down. Picking the axis from
/// the box rather than from a parameter is what keeps the wipe a token:
/// no call site has to declare an orientation, and none can get it
/// wrong.
///
/// This is a clip, not a transform: the child is laid out and painted at
/// its final size and position for every frame, which is the whole
/// reason `maskWipe` exists.
class RevealWipeClipper extends CustomClipper<Path> {
  const RevealWipeClipper({
    required this.fraction,
    required this.textDirection,
  });

  final double fraction;
  final TextDirection textDirection;

  @override
  Path getClip(Size size) {
    final f = fraction.clamp(0.0, 1.0);
    final Rect rect;
    if (size.width >= size.height) {
      final width = size.width * f;
      rect = textDirection == TextDirection.rtl
          ? Rect.fromLTWH(size.width - width, 0, width, size.height)
          : Rect.fromLTWH(0, 0, width, size.height);
    } else {
      rect = Rect.fromLTWH(0, 0, size.width, size.height * f);
    }
    return Path()..addRect(rect);
  }

  @override
  bool shouldReclip(RevealWipeClipper oldClipper) =>
      oldClipper.fraction != fraction ||
      oldClipper.textDirection != textDirection;
}
