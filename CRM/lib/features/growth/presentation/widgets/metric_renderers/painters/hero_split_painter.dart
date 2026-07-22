import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// One drawn arc of the half-pie.
@immutable
class HeroSplitArc {
  final double start;
  final double sweep;

  /// True when the segment is too small to draw as an arc and is drawn as a
  /// dot at [start] instead, so a tiny non-zero value stays visible.
  final bool sliver;

  const HeroSplitArc({
    required this.start,
    required this.sweep,
    required this.sliver,
  });
}

/// The resolved geometry of a `hero_split` half-pie.
@immutable
class HeroSplitGeometry {
  final double stroke;
  final double radius;
  final Offset centre;

  /// One entry per NON-ZERO input value, in input order.
  final List<HeroSplitArc> arcs;

  /// The input indices the arcs correspond to (zero values are dropped, and
  /// spend no gap).
  final List<int> valueIndices;

  const HeroSplitGeometry({
    required this.stroke,
    required this.radius,
    required this.centre,
    required this.arcs,
    required this.valueIndices,
  });

  Rect get rect => Rect.fromCircle(center: centre, radius: radius);
}

/// The half-pie's stroke as a fraction of its short side.
const double kHeroSplitStrokeRatio = 0.09;

/// Resolves the half-pie geometry for [values] inside [size].
///
/// The arc is drawn from π (left) sweeping π clockwise to the flat baseline
/// at the bottom of the box. Three things this deliberately gets right:
///
/// - **Radius** is `min(w / 2, h) - stroke / 2`, so the ring fits its box at
///   any aspect ratio — a radius taken off the shortest side minus the full
///   stroke overflows horizontally whenever `w < 2h` and under-fills at
///   `w == 2h`.
/// - **The outer ends** are inset by `capRad`, the round cap's own overhang
///   in radians, so the caps stop at the flat baseline instead of bulging
///   past it. The half-pie's footprint is then exactly the half-circle.
/// - **Interior joins** each give up `gapRad / 2` per side, where
///   `gapRad = spacingMedium / r`. Because the gap is derived from the
///   radius it is the SAME 8px on screen at every size and every segment
///   count — a fixed angular gap would grow and shrink with the box.
HeroSplitGeometry computeHeroSplit(Size size, List<double> values) {
  final short = math.min(size.width / 2, size.height);
  final stroke = short * kHeroSplitStrokeRatio;
  final radius = math.max(short - stroke / 2, 0.0);
  final centre = Offset(size.width / 2, size.height);

  final indices = <int>[];
  var total = 0.0;
  for (var i = 0; i < values.length; i++) {
    if (values[i] > 0) {
      indices.add(i);
      total += values[i];
    }
  }
  if (indices.isEmpty || total <= 0 || radius <= 0) {
    return HeroSplitGeometry(
      stroke: stroke,
      radius: radius,
      centre: centre,
      arcs: const [],
      valueIndices: const [],
    );
  }

  final gapRad = DesignConstants.spacingMedium / radius;
  final capRad = (stroke / 2) / radius;

  final arcs = <HeroSplitArc>[];
  var boundary = math.pi;
  for (var i = 0; i < indices.length; i++) {
    final next = boundary + math.pi * (values[indices[i]] / total);
    final start = boundary + capRad + (i == 0 ? 0 : gapRad / 2);
    final end =
        next - capRad - (i == indices.length - 1 ? 0 : gapRad / 2);
    final sweep = end - start;
    arcs.add(
      sweep > 0
          ? HeroSplitArc(start: start, sweep: sweep, sliver: false)
          : HeroSplitArc(
              start: (boundary + next) / 2,
              sweep: 0,
              sliver: true,
            ),
    );
    boundary = next;
  }

  return HeroSplitGeometry(
    stroke: stroke,
    radius: radius,
    centre: centre,
    arcs: arcs,
    valueIndices: indices,
  );
}

/// Paints an N-segment half-pie: the page's one hero figure.
///
/// With no positive value it paints the empty track once — a gym that has
/// billed nothing yet still gets the shape of the figure, with the copy
/// underneath doing the explaining.
class HeroSplitPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  final Color trackColor;

  HeroSplitPainter({
    required this.values,
    required this.colors,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = computeHeroSplit(size, values);
    if (geometry.radius <= 0) return;

    if (geometry.arcs.isEmpty) {
      canvas.drawArc(
        geometry.rect,
        math.pi,
        math.pi,
        false,
        Paint()
          ..color = trackColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = geometry.stroke,
      );
      return;
    }

    for (var i = 0; i < geometry.arcs.length; i++) {
      final arc = geometry.arcs[i];
      final index = geometry.valueIndices[i];
      final color = index < colors.length ? colors[index] : trackColor;
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = geometry.stroke
        ..strokeCap = StrokeCap.round;
      if (arc.sliver) {
        canvas.drawCircle(
          geometry.centre +
              Offset(
                geometry.radius * math.cos(arc.start),
                geometry.radius * math.sin(arc.start),
              ),
          geometry.stroke / 2,
          Paint()..color = color,
        );
      } else {
        canvas.drawArc(geometry.rect, arc.start, arc.sweep, false, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant HeroSplitPainter old) =>
      old.trackColor != trackColor ||
      !listEquals(old.values, values) ||
      !listEquals(old.colors, colors);
}
