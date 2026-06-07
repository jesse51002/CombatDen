import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// Circular progress arc — a "donut" ring showing a single percentage
/// against a muted track. Used by Growth's Monthly Churn donut tiles.
/// Sized to fill its parent — wrap in a `SizedBox` to control
/// dimensions.
///
/// `progress` is clamped to `0.0..1.0`. The arc starts at the top
/// (12 o'clock) and sweeps clockwise.
class ProgressArc extends StatelessWidget {
  final double progress;
  final Color progressColor;
  final Color? trackColor;
  final double strokeRatio;

  const ProgressArc({
    super.key,
    required this.progress,
    required this.progressColor,
    this.trackColor,
    this.strokeRatio = 0.08,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ProgressArcPainter(
        progress: progress.clamp(0.0, 1.0),
        progressColor: progressColor,
        trackColor: trackColor ?? DesignConstants.card,
        strokeRatio: strokeRatio,
      ),
    );
  }
}

class _ProgressArcPainter extends CustomPainter {
  final double progress;
  final Color progressColor;
  final Color trackColor;
  final double strokeRatio;

  _ProgressArcPainter({
    required this.progress,
    required this.progressColor,
    required this.trackColor,
    required this.strokeRatio,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.shortestSide * strokeRatio;
    final radius = (size.shortestSide - strokeWidth) / 2;
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: radius,
    );

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      radius,
      trackPaint,
    );

    const start = -math.pi / 2;
    final sweep = math.pi * 2 * progress;
    canvas.drawArc(rect, start, sweep, false, progressPaint);
  }

  @override
  bool shouldRepaint(covariant _ProgressArcPainter old) =>
      old.progress != progress ||
      old.progressColor != progressColor ||
      old.trackColor != trackColor ||
      old.strokeRatio != strokeRatio;
}
