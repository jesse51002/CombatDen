import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/growth/data/mock_growth.dart';

/// Chart visual for Members-over-time. The line is drawn with a
/// [CustomPainter] as a smooth spline through [kMockMembersTrendSeries]
/// (mirrors MobileApp's profile `RatingGraph`). Y-axis tick labels and
/// X-axis month labels are real Flutter widgets so they re-flow with
/// the design system.
class MembersTrendChart extends StatelessWidget {
  const MembersTrendChart({super.key});

  static const double _chartHeight = 200;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingBig,
      children: [
        _ChartBody(),
        _XAxisLabels(),
      ],
    );
  }
}

class _ChartBody extends StatelessWidget {
  const _ChartBody();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingLarge,
      children: [
        Expanded(
          child: SizedBox(
            height: MembersTrendChart._chartHeight,
            child: CustomPaint(
              size: Size.infinite,
              painter: _MembersTrendLinePainter(
                series: kMockMembersTrendSeries,
                color: DesignConstants.primaryColor,
              ),
            ),
          ),
        ),
        SizedBox(
          height: MembersTrendChart._chartHeight,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final tick in kMockMembersTrendYTicks)
                Text(
                  '$tick -',
                  style: DesignConstants.h2.copyWith(
                    color: DesignConstants.text3rd,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Draws [series] (normalized 0..1 y-values, evenly spaced on x) as a
/// smooth Catmull-Rom spline. Stroke-only, no fill, no point markers —
/// matching MobileApp's profile `RatingGraph`.
class _MembersTrendLinePainter extends CustomPainter {
  final List<double> series;
  final Color color;

  // Chart line weight. The shared design system has no line-stroke
  // token; MobileApp's RatingGraph hardcodes the same 3px locally.
  static const double _strokeWidth = 3;

  _MembersTrendLinePainter({required this.series, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (series.length < 2) return;

    final points = <Offset>[
      for (var i = 0; i < series.length; i++)
        Offset(
          size.width * (i / (series.length - 1)),
          size.height * (1 - series[i].clamp(0.0, 1.0)),
        ),
    ];

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 0; i < points.length - 1; i++) {
      final p0 = i == 0 ? points[0] : points[i - 1];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = i + 2 < points.length ? points[i + 2] : points[i + 1];

      final cp1 = Offset(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
      );
      final cp2 = Offset(
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
      );

      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
    }

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_MembersTrendLinePainter old) =>
      old.color != color || old.series != series;
}

class _XAxisLabels extends StatelessWidget {
  const _XAxisLabels();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final label in kMockMembersTrendXLabels)
          Text(
            label,
            textAlign: TextAlign.center,
            style: DesignConstants.p.copyWith(
              color: DesignConstants.text2nd,
            ),
          ),
      ],
    );
  }
}
