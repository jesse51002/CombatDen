import 'package:flutter/animation.dart';
import 'package:mobile_app/core/formats/motion_formats.dart';
import 'package:mobile_app/shared/widgets/animation/loader/loader_frame.dart';

// One loader's timing math, file-scoped per CLAUDE.md's `_k` carve-out.
const Duration _kCycle = Duration(milliseconds: 1300);
// Two rings, half a cycle apart. One ring would leave the box briefly
// empty at the wrap; two means a ripple is always on screen, including
// at mount — a waiting state that shows nothing for a beat reads as a
// freeze, which is the opposite of what a loader is for.
const int _kRingCount = 2;
// Where a ring is born. Not zero: a ring starting from nothing reads as
// a dot appearing rather than as a ripple leaving the centre.
const double _kBirthScale = 0.18;
// Fraction of a ring's life spent fading in. Short, for the same reason
// the count is two — the loader has to be legible immediately.
const double _kFadeIn = 0.12;

/// `LoaderStyle.pulseRing` — a ring scales out and fades, repeating.
///
/// Ease-out: the ring leaves the centre quickly and slows as it reaches
/// the edge, arriving at exactly its settled radius and never past it.
const LoaderSpec kPulseRingLoader = LoaderSpec(
  value: LoaderStyle.pulseRing,
  shape: LoaderShape.ring,
  cycle: _kCycle,
  markCount: _kRingCount,
  frameAt: _frameAt,
);

LoaderFrame _frameAt(double t) => LoaderFrame([
  for (var i = 0; i < _kRingCount; i++) _ring((t + i / _kRingCount) % 1.0),
]);

LoaderMark _ring(double phase) {
  final spread = Curves.easeOutQuart.transform(phase);
  final fadeIn = (phase / _kFadeIn).clamp(0.0, 1.0);
  return LoaderMark(
    scale: _kBirthScale + (1 - _kBirthScale) * spread,
    // Zero at both ends of a ring's life, so the wrap is invisible.
    opacity: fadeIn * (1 - phase),
  );
}
