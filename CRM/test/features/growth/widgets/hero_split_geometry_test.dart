import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/growth/presentation/widgets/metric_renderers/painters/hero_split_painter.dart';

void main() {
  group('computeHeroSplit', () {
    test('the ring fits its box at any aspect ratio', () {
      // The bug this replaces: a radius of `shortestSide - stroke` overflows
      // horizontally whenever w < 2h.
      for (final size in const [
        Size(400, 200),
        Size(300, 200),
        Size(200, 200),
        Size(600, 200),
      ]) {
        final geometry = computeHeroSplit(size, [1, 1]);
        final outer = geometry.radius + geometry.stroke / 2;
        expect(
          outer,
          lessThanOrEqualTo(size.width / 2 + 0.001),
          reason: 'overflows horizontally at $size',
        );
        expect(
          outer,
          lessThanOrEqualTo(size.height + 0.001),
          reason: 'overflows vertically at $size',
        );
      }
    });

    test('fills the box exactly at the 2:1 hero ratio', () {
      final geometry = computeHeroSplit(const Size(400, 200), [1, 1]);
      expect(geometry.radius + geometry.stroke / 2, closeTo(200, 0.001));
    });

    test('round caps stay inside the flat baseline', () {
      final geometry = computeHeroSplit(const Size(400, 200), [3, 1]);
      final first = geometry.arcs.first;
      final last = geometry.arcs.last;
      // Both outer ends are inset by the cap's own overhang.
      expect(first.start, greaterThan(math.pi));
      expect(last.start + last.sweep, lessThan(2 * math.pi));
    });

    test('the interior gap is the same 8px at every size', () {
      // The gap the eye sees is between the two round CAP EDGES, so the
      // centreline gap carries one cap overhang (stroke / 2) per side on top
      // of the 8px surface gap.
      for (final size in const [Size(400, 200), Size(200, 100)]) {
        final geometry = computeHeroSplit(size, [1, 1]);
        final gapRadians = geometry.arcs[1].start -
            (geometry.arcs[0].start + geometry.arcs[0].sweep);
        final visibleGap = gapRadians * geometry.radius - geometry.stroke;
        expect(
          visibleGap,
          closeTo(DesignConstants.spacingMedium, 0.001),
          reason: 'gap is not radius-independent at $size',
        );
      }
    });

    test('zero segments are dropped and spend no gap', () {
      final geometry = computeHeroSplit(const Size(400, 200), [10, 0, 5]);
      expect(geometry.arcs.length, 2);
      expect(geometry.valueIndices, [0, 2]);
      // The two drawn sweeps still split the half-circle 2:1.
      expect(
        geometry.arcs[0].sweep / geometry.arcs[1].sweep,
        greaterThan(1.5),
      );
    });

    test('a sliver too small to draw becomes a dot, not nothing', () {
      final geometry = computeHeroSplit(const Size(400, 200), [1000, 0.01]);
      expect(geometry.arcs.last.sliver, isTrue);
    });

    test('no positive value yields no arcs (the empty track is drawn)', () {
      final geometry = computeHeroSplit(const Size(400, 200), [0, 0]);
      expect(geometry.arcs, isEmpty);
    });
  });
}
