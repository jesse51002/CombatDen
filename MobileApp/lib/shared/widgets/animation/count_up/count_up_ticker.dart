import 'package:flutter/animation.dart';
import 'package:mobile_app/core/formats/motion_formats.dart';
import 'package:mobile_app/shared/widgets/animation/count_up/count_up_frame.dart';

// One value's timing math, file-scoped per CLAUDE.md's `_k` carve-out.
//
// The lead-in: the figure holds on its opening zeros for a beat before
// the roll starts, so the eye has time to register that something is
// about to happen rather than finding the number already resolved. Kept
// under `kFlipCountIntro.handoff` (310ms) on purpose — that intro hands
// the card over mid-flip specifically so the count is already running
// while the hero is still turning, and a longer hold would push the roll
// out past the flip it is meant to overlap.
const double _kLeadIn = 0.16; // ~224ms of the 1400ms reference.

/// `CountUpStyle.ticker` — the cheap one.
///
/// No per-digit motion at all: the whole number simply re-renders
/// through its intermediate values, one glyph per position. Where
/// `odometer` builds a strip of every integer each position will pass
/// through, this builds one digit per position and swaps it — a handful
/// of glyphs instead of hundreds, which is what makes it the value to
/// reach for on a surface that cannot afford the reels.
///
/// It rolls on ease-out-quad rather than the odometer's ease-out-expo:
/// the numbers here are meant to be read on the way up, not blurred
/// through, so the deceleration is gentle and the figure spends most of
/// its window on values a person can actually follow.
const CountUpSpec kTickerCountUp = CountUpSpec(
  value: CountUpStyle.ticker,
  scale: 1,
  reeled: false,
  hasArc: false,
  frameAt: _frameAt,
);

CountUpFrame _frameAt(double t) {
  final roll = ((t.clamp(0.0, 1.0) - _kLeadIn) / (1 - _kLeadIn)).clamp(
    0.0,
    1.0,
  );
  return CountUpFrame(progress: Curves.easeOutQuad.transform(roll));
}
