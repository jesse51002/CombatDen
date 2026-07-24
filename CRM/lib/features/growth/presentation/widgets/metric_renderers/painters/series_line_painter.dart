import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/series/drawn_series.dart';

/// Centre x of bucket [index] in a `line` plot [plotWidth] wide.
///
/// Shared by the painter, the axis labels and the hover hit-test so all
/// three agree on where a bucket lives. A single bucket sits centred.
double lineXOf(int index, int bucketCount, double plotWidth) {
  if (bucketCount <= 1) return plotWidth / 2;
  return plotWidth * (index / (bucketCount - 1));
}

/// Paints one to three series as smooth Catmull-Rom splines over solid
/// gridlines, with an end marker (and optionally a direct end label) at each
/// series' newest point.
///
/// A null value is a GAP, not a zero: the spline breaks and resumes.
class SeriesLinePainter extends CustomPainter {
  final List<DrawnSeries> series;

  /// The nice ceiling the y axis was drawn against.
  final double maxY;

  /// Tick values (in data units) to draw a gridline at.
  final List<double> gridTicks;

  /// Single-series charts get a 10% area wash; two washes muddle.
  final bool areaFill;

  /// Series indices whose newest value is labelled directly on the plot.
  final Set<int> endLabeled;

  /// Pre-formatted end labels, by series index.
  final Map<int, String> endLabels;

  final Color gridColor;
  final Color surfaceColor;
  final TextStyle labelStyle;

  SeriesLinePainter({
    required this.series,
    required this.maxY,
    required this.gridTicks,
    required this.areaFill,
    required this.endLabeled,
    required this.endLabels,
    required this.gridColor,
    required this.surfaceColor,
    required this.labelStyle,
  });

  int get _bucketCount =>
      series.fold(0, (max, s) => s.values.length > max ? s.values.length : max);

  double _yOf(double value, double height) {
    if (maxY <= 0) return height;
    return height * (1 - (value / maxY).clamp(0.0, 1.0));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    _paintGrid(canvas, size);

    final buckets = _bucketCount;
    if (buckets == 0) return;

    for (final s in series) {
      final runs = _runsOf(s, buckets, size);
      for (final run in runs) {
        if (run.length < 2) continue;
        final path = _splinePath(run);
        if (areaFill && series.length == 1) {
          final area = Path.from(path)
            ..lineTo(run.last.dx, size.height)
            ..lineTo(run.first.dx, size.height)
            ..close();
          canvas.drawPath(
            area,
            Paint()..color = s.color.withValues(alpha: 0.1),
          );
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = s.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = DesignConstants.chartStroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
    }

    _paintEndMarkers(canvas, size, buckets);
  }

  void _paintGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = DesignConstants.dividerThickness;
    for (final tick in gridTicks) {
      final y = _yOf(tick, size.height);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  /// The contiguous runs of drawn points — one per unbroken stretch of
  /// non-null values.
  List<List<Offset>> _runsOf(DrawnSeries s, int buckets, Size size) {
    final runs = <List<Offset>>[];
    var current = <Offset>[];
    for (var i = 0; i < buckets; i++) {
      final value = i < s.values.length ? s.values[i] : null;
      if (value == null) {
        if (current.isNotEmpty) runs.add(current);
        current = <Offset>[];
        continue;
      }
      current.add(
        Offset(lineXOf(i, buckets, size.width), _yOf(value, size.height)),
      );
    }
    if (current.isNotEmpty) runs.add(current);
    return runs;
  }

  Path _splinePath(List<Offset> points) {
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
    return path;
  }

  void _paintEndMarkers(Canvas canvas, Size size, int buckets) {
    final anchors = <int, Offset>{};
    for (var i = 0; i < series.length; i++) {
      final at = series[i].lastIndex;
      if (at < 0) continue;
      anchors[i] = Offset(
        lineXOf(at, buckets, size.width),
        _yOf(series[i].values[at]!, size.height),
      );
    }

    for (final entry in anchors.entries) {
      final color = series[entry.key].color;
      canvas.drawCircle(
        entry.value,
        DesignConstants.spacingSmall + DesignConstants.chartStroke,
        Paint()..color = surfaceColor,
      );
      canvas.drawCircle(
        entry.value,
        DesignConstants.spacingSmall,
        Paint()..color = color,
      );
    }

    for (final index in _labelledSeries(anchors)) {
      final text = endLabels[index];
      final anchor = anchors[index];
      if (text == null || anchor == null) continue;
      final painter = TextPainter(
        text: TextSpan(text: text, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = (anchor.dx - painter.width - DesignConstants.spacingMedium)
          .clamp(0.0, (size.width - painter.width).clamp(0.0, size.width));
      final dy = (anchor.dy - painter.height - DesignConstants.spacingMedium)
          .clamp(0.0, (size.height - painter.height).clamp(0.0, size.height));
      painter.paint(canvas, Offset(dx, dy));
    }
  }

  /// Drops every direct end label that would crowd another one — the legend
  /// still carries the value, so a collided pair loses nothing.
  Iterable<int> _labelledSeries(Map<int, Offset> anchors) {
    final candidates = endLabeled.where(anchors.containsKey).toList();
    final crowded = <int>{};
    for (var a = 0; a < candidates.length; a++) {
      for (var b = a + 1; b < candidates.length; b++) {
        final ya = anchors[candidates[a]]!.dy;
        final yb = anchors[candidates[b]]!.dy;
        if ((ya - yb).abs() < DesignConstants.spacingLarge) {
          crowded
            ..add(candidates[a])
            ..add(candidates[b]);
        }
      }
    }
    return candidates.where((i) => !crowded.contains(i));
  }

  @override
  bool shouldRepaint(covariant SeriesLinePainter old) =>
      old.maxY != maxY ||
      old.areaFill != areaFill ||
      old.gridColor != gridColor ||
      old.surfaceColor != surfaceColor ||
      old.labelStyle != labelStyle ||
      !listEquals(old.series, series) ||
      !listEquals(old.gridTicks, gridTicks) ||
      !setEquals(old.endLabeled, endLabeled) ||
      !mapEquals(old.endLabels, endLabels);
}
