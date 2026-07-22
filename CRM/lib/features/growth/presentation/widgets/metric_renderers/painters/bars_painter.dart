import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/series/drawn_series.dart';

/// How a `bars` metric is drawn. Chosen deterministically from the series
/// count and the metric key — never from the data's magnitudes.
enum BarsMode {
  /// 1-2 peer series side by side in each bucket.
  grouped,

  /// 3 series stacked bottom-up, S1 at the bottom.
  stacked,

  /// A good/bad pair: good grows up, bad grows down off a centre baseline.
  ///
  /// Position — not hue — is the identity channel here, which is required:
  /// green and red collapse to a ~ΔE 3 difference under deuteranopia, so
  /// colour alone could never separate the two halves.
  diverging,
}

/// Centre x of bucket [index] in a `bars` plot [plotWidth] wide.
double barsXOf(int index, int bucketCount, double plotWidth) {
  if (bucketCount <= 0) return plotWidth / 2;
  final slot = plotWidth / bucketCount;
  return slot * (index + 0.5);
}

/// Paints a bucketed bar chart in one of the three [BarsMode]s.
class BarsPainter extends CustomPainter {
  final List<DrawnSeries> series;
  final BarsMode mode;

  /// The nice ceiling. In [BarsMode.diverging] it is the magnitude at each
  /// end of the symmetric scale.
  final double maxY;

  /// Tick values to draw a gridline at, in data units.
  final List<double> gridTicks;

  /// Total printed above the newest bucket of a stacked chart; null when the
  /// mode does not carry one.
  final String? newestTotalLabel;

  final Color gridColor;
  final Color surfaceColor;
  final TextStyle labelStyle;

  BarsPainter({
    required this.series,
    required this.mode,
    required this.maxY,
    required this.gridTicks,
    required this.newestTotalLabel,
    required this.gridColor,
    required this.surfaceColor,
    required this.labelStyle,
  });

  int get bucketCount =>
      series.fold(0, (max, s) => s.values.length > max ? s.values.length : max);

  double get _baselineFactor => mode == BarsMode.diverging ? 0.5 : 1.0;

  double _yOf(double value, double height) {
    final baseline = height * _baselineFactor;
    if (maxY <= 0) return baseline;
    final span = mode == BarsMode.diverging ? height / 2 : height;
    return baseline - (value / maxY).clamp(-1.0, 1.0) * span;
  }

  double _barWidth(double plotWidth, int drawnSeries) {
    final slot = plotWidth / math.max(bucketCount, 1);
    final grouped = mode == BarsMode.grouped || mode == BarsMode.diverging;
    final width = grouped
        ? ((slot - DesignConstants.spacingMedium) -
                DesignConstants.spacingSmall * (drawnSeries - 1)) /
            drawnSeries
        : slot - DesignConstants.spacingMedium;
    return width.clamp(1.0, DesignConstants.chartBarMaxWidth);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || bucketCount == 0) return;
    _paintGrid(canvas, size);
    switch (mode) {
      case BarsMode.grouped:
        _paintGrouped(canvas, size);
      case BarsMode.stacked:
        _paintStacked(canvas, size);
      case BarsMode.diverging:
        _paintDiverging(canvas, size);
    }
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

  /// Bars grow from the baseline with the two DATA-END corners rounded and
  /// square feet at the baseline.
  void _drawBar(Canvas canvas, Rect rect, Color color, {required bool up}) {
    if (rect.height <= 0 || rect.width <= 0) return;
    final radius = Radius.circular(
      math.min(DesignConstants.radiusSmall, rect.width / 2),
    );
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        rect,
        topLeft: up ? radius : Radius.zero,
        topRight: up ? radius : Radius.zero,
        bottomLeft: up ? Radius.zero : radius,
        bottomRight: up ? Radius.zero : radius,
      ),
      Paint()..color = color,
    );
  }

  void _paintGrouped(Canvas canvas, Size size) {
    final drawn = series.length;
    final barW = _barWidth(size.width, drawn);
    final groupW =
        barW * drawn + DesignConstants.spacingSmall * (drawn - 1);
    for (var b = 0; b < bucketCount; b++) {
      final centre = barsXOf(b, bucketCount, size.width);
      var left = centre - groupW / 2;
      for (final s in series) {
        final value = b < s.values.length ? s.values[b] : null;
        if (value != null && value > 0) {
          final top = _yOf(value, size.height);
          _drawBar(
            canvas,
            Rect.fromLTRB(left, top, left + barW, size.height),
            s.color,
            up: true,
          );
        }
        left += barW + DesignConstants.spacingSmall;
      }
    }
  }

  void _paintStacked(Canvas canvas, Size size) {
    final barW = _barWidth(size.width, 1);
    for (var b = 0; b < bucketCount; b++) {
      final centre = barsXOf(b, bucketCount, size.width);
      final left = centre - barW / 2;
      var runningTotal = 0.0;
      // The topmost drawn segment is the only one that gets a rounded top.
      var topSegment = -1;
      for (var i = 0; i < series.length; i++) {
        final v = b < series[i].values.length ? series[i].values[b] : null;
        if (v != null && v > 0) topSegment = i;
      }
      for (var i = 0; i < series.length; i++) {
        final value = b < series[i].values.length ? series[i].values[b] : null;
        if (value == null || value <= 0) continue;
        final bottom = _yOf(runningTotal, size.height);
        runningTotal += value;
        final rawTop = _yOf(runningTotal, size.height);
        // A surface gap between stacked segments, never a stroke.
        final top = i == topSegment
            ? rawTop
            : math.min(rawTop + DesignConstants.spacingSmall, bottom);
        final rect = Rect.fromLTRB(left, top, left + barW, bottom);
        if (i == topSegment) {
          _drawBar(canvas, rect, series[i].color, up: true);
        } else {
          canvas.drawRect(rect, Paint()..color = series[i].color);
        }
      }
      final label = newestTotalLabel;
      if (label != null && b == bucketCount - 1 && runningTotal > 0) {
        _paintTotal(canvas, size, label, centre, _yOf(runningTotal, size.height));
      }
    }
  }

  void _paintTotal(
    Canvas canvas,
    Size size,
    String label,
    double centre,
    double top,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = (centre - painter.width / 2)
        .clamp(0.0, (size.width - painter.width).clamp(0.0, size.width));
    final dy = (top - painter.height - DesignConstants.spacingSmall)
        .clamp(0.0, (size.height - painter.height).clamp(0.0, size.height));
    painter.paint(canvas, Offset(dx, dy));
  }

  void _paintDiverging(Canvas canvas, Size size) {
    final barW = _barWidth(size.width, 1);
    final baseline = size.height / 2;
    for (var b = 0; b < bucketCount; b++) {
      final centre = barsXOf(b, bucketCount, size.width);
      final left = centre - barW / 2;
      for (var i = 0; i < series.length; i++) {
        final value = b < series[i].values.length ? series[i].values[b] : null;
        if (value == null || value == 0) continue;
        // Series 0 is the good half (up); everything after grows down.
        final magnitude = value.abs();
        final up = i == 0;
        final end = _yOf(up ? magnitude : -magnitude, size.height);
        _drawBar(
          canvas,
          Rect.fromLTRB(
            left,
            up ? end : baseline,
            left + barW,
            up ? baseline : end,
          ),
          series[i].color,
          up: up,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant BarsPainter old) =>
      old.mode != mode ||
      old.maxY != maxY ||
      old.newestTotalLabel != newestTotalLabel ||
      old.gridColor != gridColor ||
      old.surfaceColor != surfaceColor ||
      old.labelStyle != labelStyle ||
      !listEquals(old.series, series) ||
      !listEquals(old.gridTicks, gridTicks);
}
