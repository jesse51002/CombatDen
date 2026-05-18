import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/features/profile/data/mock_profile.dart';
import 'package:mobile_app/shared/widgets/text/threshold_label.dart';

const List<double> _kThresholdTopOffsets = [12, 80, 140];

const double _kStrokeWidth = 3;

/// Rating-over-time line graph with rank threshold annotations on the right
/// edge.
class RatingGraph extends StatelessWidget {
  const RatingGraph({super.key});

  @override
  Widget build(BuildContext context) {
    final thresholds = ratingGraphThresholds;
    final lineColor = DesignConstants.text;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: DesignConstants.screenHorizontalPadding,
      ),
      child: AspectRatio(
        aspectRatio: 393 / 196.5,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _RatingGraphPainter(
                  series: mockRatingGraphSeries,
                  color: lineColor,
                ),
              ),
            ),
            for (var i = 0; i < thresholds.length; i++)
              Positioned(
                right: 0,
                top: _kThresholdTopOffsets[i],
                child: ThresholdLabel(label: thresholds[i]),
              ),
          ],
        ),
      ),
    );
  }
}

class _RatingGraphPainter extends CustomPainter {
  _RatingGraphPainter({required this.series, required this.color});

  final List<double> series;
  final Color color;

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
      ..strokeWidth = _kStrokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_RatingGraphPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.series != series;
  }
}
