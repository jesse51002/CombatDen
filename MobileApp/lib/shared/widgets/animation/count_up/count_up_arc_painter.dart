import 'dart:math' as math;

import 'package:flutter/material.dart';

// Arc geometry, file-scoped per CLAUDE.md's `_k` carve-out: this is one
// decoration's layout math, not a fungible design token. The depth is a
// fraction of the figure's own height so the arc scales with whatever
// type size the call site hands the count-up.
const double _kArcDepth = 0.11;

/// Paints `sweepArc`'s arc beneath the figure.
///
/// Given to `CustomPaint` as its `painter` (never `foregroundPainter`),
/// so it draws behind the digits, and always WITH a child, so the render
/// object takes the figure's size and the arc contributes nothing to
/// layout. That is the whole reason the arc cannot resize the count-up
/// when it settles.
///
/// The geometry stays inside the figure's bounds: a shallow bowl whose
/// lowest point sits half a stroke above the bottom edge, swept left to
/// right.
class CountUpArcPainter extends CustomPainter {
  const CountUpArcPainter({
    required this.sweep,
    required this.opacity,
    required this.color,
    required this.strokeWidth,
  });

  /// 0..1 fraction of the bowl that has been drawn.
  final double sweep;
  final double opacity;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final drawn = sweep.clamp(0.0, 1.0);
    final alpha = opacity.clamp(0.0, 1.0);
    if (drawn <= 0 || alpha <= 0 || size.isEmpty) return;

    final inset = strokeWidth / 2;
    final depth = size.height * _kArcDepth;
    final centerY = size.height - inset - depth;
    if (size.width <= strokeWidth || depth <= 0) return;

    final bounds = Rect.fromLTRB(
      inset,
      centerY - depth,
      size.width - inset,
      centerY + depth,
    );

    canvas.drawArc(
      bounds,
      // From the left-hand end, sweeping negatively through the bottom
      // of the ellipse to the right-hand end: left to right, under the
      // figure.
      math.pi,
      -math.pi * drawn,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = strokeWidth
        ..color = color.withValues(alpha: alpha),
    );
  }

  @override
  bool shouldRepaint(CountUpArcPainter oldDelegate) =>
      oldDelegate.sweep != sweep ||
      oldDelegate.opacity != opacity ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}
