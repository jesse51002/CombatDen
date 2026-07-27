import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/text/threshold_label.dart';

const double _kStrokeWidth = 3;
const double _kGraphAspect = 393 / 196.5;

/// Rank-progress line graph: the member's classes-into-rank sawtooth
/// (normalized 0..1, resetting to 0 at each promotion) with the classes axis
/// bracketed on the right edge — [classesNeeded] (the promotion line) at the
/// top, `0` at the bottom. A too-short / empty series renders a graceful empty
/// state instead of a blank box.
class RatingGraph extends StatelessWidget {
  const RatingGraph({
    super.key,
    required this.series,
    required this.classesNeeded,
  });

  /// The normalized 0..1 y-values, spaced uniformly across the width.
  final List<double> series;

  /// The next-rank threshold in classes — the value at the top of the axis.
  final int classesNeeded;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: DesignConstants.screenHorizontalPadding,
      ),
      child: AspectRatio(
        aspectRatio: _kGraphAspect,
        child: series.length < 2
            ? const _GraphEmpty()
            : _GraphPlot(series: series, classesNeeded: classesNeeded),
      ),
    );
  }
}

/// The plotted line with the two classes-axis reference labels on the right.
class _GraphPlot extends StatelessWidget {
  const _GraphPlot({required this.series, required this.classesNeeded});

  final List<double> series;
  final int classesNeeded;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _RatingGraphPainter(
              series: series,
              color: DesignConstants.text,
            ),
          ),
        ),
        if (classesNeeded > 0)
          Positioned(
            right: 0,
            top: 0,
            child: ThresholdLabel(label: '$classesNeeded'),
          ),
        const Positioned(
          right: 0,
          bottom: 0,
          child: ThresholdLabel(label: '0'),
        ),
      ],
    );
  }
}

/// Shown when the series has no plottable history (no rank / no activity yet).
class _GraphEmpty extends StatelessWidget {
  const _GraphEmpty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No rank history yet.',
        textAlign: TextAlign.center,
        style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
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
