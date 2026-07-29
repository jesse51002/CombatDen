import 'dart:math' as math;

import 'package:mobile_app/core/formats/motion_formats.dart';
import 'package:mobile_app/shared/widgets/animation/loader/loader_frame.dart';

// The shipped loader's numbers, carried over verbatim from the
// hand-rolled dot wave this replaced. File-scoped per CLAUDE.md's `_k`
// carve-out: one loader's timing math, not app tokens.
const int _kDotCount = 3;
const Duration _kCycle = Duration(milliseconds: 1100);

/// `LoaderStyle.dots` — the value that ships.
///
/// Three brand dots in a travelling wave. Each dot is offset by 1/3 of a
/// cycle, so the bounce reads as a single ripple crossing the row and
/// coming back. The lift is a half-sine: 0 at rest, 1 at the peak, 0 at
/// rest, with the dot flat on the baseline for the half of its phase the
/// sine spends negative.
const LoaderSpec kDotsLoader = LoaderSpec(
  value: LoaderStyle.dots,
  shape: LoaderShape.dot,
  cycle: _kCycle,
  markCount: _kDotCount,
  frameAt: _frameAt,
);

LoaderFrame _frameAt(double t) => LoaderFrame([
  for (var i = 0; i < _kDotCount; i++)
    LoaderMark(
      // Evenly spaced across the row: -1, 0, 1 for three dots.
      x: i / (_kDotCount - 1) * 2 - 1,
      lift: math.max(
        0.0,
        math.sin(((t + i / _kDotCount) % 1.0) * 2 * math.pi),
      ),
    ),
]);
