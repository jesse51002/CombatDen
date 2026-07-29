import 'package:flutter/animation.dart';
import 'package:mobile_app/core/formats/motion_formats.dart';
import 'package:mobile_app/shared/widgets/animation/count_up/count_up_frame.dart';

// One value's timing math, file-scoped per CLAUDE.md's `_k` carve-out.
//
// The arc is this value's lead-in: it starts moving immediately, so the
// eye is drawn to the figure before the figure itself does anything. The
// hold that follows is deliberately short — `kFlipCountIntro` hands the
// card over mid-flip (at 310ms) so the count is already running while the
// hero turns, and a longer hold would push the roll past that flip.
const double _kHold = 0.2; // ~280ms of the 1400ms reference.
const double _kArcFadeIn = 0.08;
const double _kArcSweepEnd = 0.55;
const double _kArcFadeStart = 0.75;

/// `CountUpStyle.sweepArc` — the one that announces the figure before it
/// moves.
///
/// An arc sweeps left to right beneath the number while the number
/// itself holds on its opening zeros; then the figure rolls up to its
/// value while the arc completes and clears, so the two settle together.
///
/// The arc is a transient, exactly like the celebration intro's hero:
/// it is fully faded by the time the value lands, so what is left at rest
/// is the same figure, in the same box, that every other value leaves.
/// It is painted BEHIND the figure by the shared count-up figure widget,
/// inside the figure's own bounds, so it cannot move or resize the
/// surface it decorates — settled or mid-sweep.
const CountUpSpec kSweepArcCountUp = CountUpSpec(
  value: CountUpStyle.sweepArc,
  scale: 1,
  reeled: false,
  hasArc: true,
  frameAt: _frameAt,
);

CountUpFrame _frameAt(double t) {
  final clamped = t.clamp(0.0, 1.0);
  final roll = ((clamped - _kHold) / (1 - _kHold)).clamp(0.0, 1.0);
  final sweep = (clamped / _kArcSweepEnd).clamp(0.0, 1.0);
  final fadeIn = (clamped / _kArcFadeIn).clamp(0.0, 1.0);
  final fadeOut = ((clamped - _kArcFadeStart) / (1 - _kArcFadeStart)).clamp(
    0.0,
    1.0,
  );

  return CountUpFrame(
    progress: Curves.easeOutQuad.transform(roll),
    arcSweep: Curves.easeOutCubic.transform(sweep),
    arcOpacity:
        Curves.easeOut.transform(fadeIn) *
        (1 - Curves.easeOut.transform(fadeOut)),
  );
}
