import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/animation/loader/loader_box.dart';
import 'package:mobile_app/shared/widgets/animation/loader/loader_frame.dart';

/// Paints [LoaderShape.ring] marks: brand rings leaving the centre of
/// the box.
///
/// A ring is a stroke, not a fill, so it cannot be a scaled box — the
/// stroke would thicken as the ring grew. The radius carries the motion
/// and the stroke stays put, which is also why this is the one shape
/// that paints on a canvas instead of composing widgets.
class LoaderRingField extends StatelessWidget {
  const LoaderRingField({super.key, required this.marks, required this.box});

  final List<LoaderMark> marks;
  final LoaderBox box;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: box.size,
      painter: _RingPainter(
        marks: marks,
        color: DesignConstants.primaryColor,
        stroke: DesignConstants.buttonBorderSize,
        liftSpan: box.liftSpan,
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.marks,
    required this.color,
    required this.stroke,
    required this.liftSpan,
  });

  final List<LoaderMark> marks;
  final Color color;
  final double stroke;
  final double liftSpan;

  @override
  void paint(Canvas canvas, Size size) {
    final maxRadius = math.min(size.width, size.height) / 2 - stroke / 2;
    if (maxRadius <= 0) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    for (final mark in marks) {
      final opacity = mark.opacity.clamp(0.0, 1.0);
      if (opacity == 0) continue;
      canvas.drawCircle(
        Offset(
          size.width / 2 + mark.x * (size.width / 2 - maxRadius),
          size.height / 2 - mark.lift * liftSpan,
        ),
        maxRadius * mark.scale.clamp(0.0, 1.0),
        paint..color = color.withValues(alpha: opacity),
      );
    }
  }

  // A loader never stops, so every frame carries a new mark list; there
  // is nothing to compare that would ever let a repaint be skipped.
  @override
  bool shouldRepaint(_RingPainter old) => true;
}
