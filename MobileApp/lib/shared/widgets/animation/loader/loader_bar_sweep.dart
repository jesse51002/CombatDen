import 'dart:math' as math;

import 'package:mobile_app/core/formats/motion_formats.dart';
import 'package:mobile_app/shared/widgets/animation/loader/loader_frame.dart';

// One loader's timing math, file-scoped per CLAUDE.md's `_k` carve-out.
// A cycle is one ROUND TRIP, so a single traverse reads at about half
// this — brisk without being agitated.
const Duration _kCycle = Duration(milliseconds: 1200);
// The bar's length as a fraction of its track. Long enough to read as a
// bar rather than a dot, short enough that the sweep is the point.
const double _kBarLength = 0.38;

/// `LoaderStyle.barSweep` — an indeterminate bar sweeping its track.
///
/// The sweep is a full there-and-back on the same half-cosine the
/// shipped dots bounce on. It arrives at each end of the track with zero
/// velocity, so the loop closes on itself instead of cutting back to the
/// start once a cycle, and the bar is never outside its track — the
/// track is the settled bound, and nothing here passes it.
const LoaderSpec kBarSweepLoader = LoaderSpec(
  value: LoaderStyle.barSweep,
  shape: LoaderShape.bar,
  cycle: _kCycle,
  markCount: 1,
  frameAt: _frameAt,
);

LoaderFrame _frameAt(double t) => LoaderFrame([
  LoaderMark(x: -math.cos(t * 2 * math.pi), scale: _kBarLength),
]);
