import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A progress arc: an optional full-circle track, then the swept
/// portion, both starting at twelve o'clock and running clockwise.
///
/// Shared by the ring that hugs the belt badge and the large arc the
/// `progressFirst` arrangement puts the belt inside, so both read as
/// the same indicator at two sizes.
class RankArcPainter extends CustomPainter {
  RankArcPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
    this.trackColor,
  });

  final double progress;
  final Color color;
  final Color? trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(strokeWidth / 2);
    final track = trackColor;
    if (track != null) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2,
        false,
        Paint()
          ..color = track
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth,
      );
    }
    canvas.drawArc(
      rect,
      -math.pi / 2,
      progress.clamp(0.0, 1.0) * math.pi * 2,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant RankArcPainter old) {
    return old.progress != progress ||
        old.color != color ||
        old.trackColor != trackColor ||
        old.strokeWidth != strokeWidth;
  }
}
