import 'dart:math' as math;

import 'package:mobile_app/core/formats/motion_formats.dart';
import 'package:mobile_app/shared/widgets/animation/loader/loader_frame.dart';

// One loader's timing math, file-scoped per CLAUDE.md's `_k` carve-out.
// A real breath, not a heartbeat: slow enough to read as alive, and the
// slowest of the four on purpose. Values do not have to match tempo —
// they have to be legible, and this is the calm end of legible.
const Duration _kCycle = Duration(milliseconds: 2400);
// The mark never grows past its settled size — it breathes IN from
// below it, so the tenant's logo is never distorted upward.
const double _kFloorScale = 0.94;

/// `LoaderStyle.logoBreathe` — the tenant mark breathing.
///
/// The only value that is white-label native: the mark is already a
/// customization slot, so this loader is the tenant's own identity
/// rather than a brand-coloured abstraction of it.
const LoaderSpec kLogoBreatheLoader = LoaderSpec(
  value: LoaderStyle.logoBreathe,
  shape: LoaderShape.mark,
  cycle: _kCycle,
  markCount: 1,
  frameAt: _frameAt,
);

LoaderFrame _frameAt(double t) {
  // Half-cosine, so the breath turns at both ends with zero velocity and
  // the loop closes on itself.
  final breath = 0.5 - 0.5 * math.cos(t * 2 * math.pi);
  return LoaderFrame([
    LoaderMark(scale: _kFloorScale + (1 - _kFloorScale) * breath),
  ]);
}
