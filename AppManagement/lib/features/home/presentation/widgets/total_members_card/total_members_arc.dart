import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:app_management/core/constants/design_constants.dart';

/// Semicircular arc that visualises the active/inactive split of total
/// members. The bright orange portion = active members, the dark portion
/// = inactive. Sized to fill its parent — wrap in a `SizedBox` to control
/// dimensions.
class TotalMembersArc extends StatelessWidget {
  final int active;
  final int inactive;

  const TotalMembersArc({
    super.key,
    required this.active,
    required this.inactive,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ArcPainter(
        active: active,
        inactive: inactive,
        activeColor: DesignConstants.primaryColor,
        inactiveColor: DesignConstants.darkPrimary,
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  final int active;
  final int inactive;
  final Color activeColor;
  final Color inactiveColor;

  _ArcPainter({
    required this.active,
    required this.inactive,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final total = active + inactive;
    if (total == 0) return;

    final strokeWidth = size.shortestSide * 0.06;
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height),
      radius: size.shortestSide - strokeWidth,
    );

    // Full half-circle = pi radians, drawn from left (pi) sweeping pi
    // back up to the right side.
    const startAngle = math.pi;
    const totalSweep = math.pi;

    final activeSweep = totalSweep * (active / total);
    final inactiveSweep = totalSweep - activeSweep;

    final activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final inactivePaint = Paint()
      ..color = inactiveColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, startAngle, activeSweep, false, activePaint);
    canvas.drawArc(
      rect,
      startAngle + activeSweep,
      inactiveSweep,
      false,
      inactivePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ArcPainter old) =>
      old.active != active ||
      old.inactive != inactive ||
      old.activeColor != activeColor ||
      old.inactiveColor != inactiveColor;
}
