import 'package:flutter/animation.dart';
import 'package:mobile_app/core/formats/motion_formats.dart';
import 'package:mobile_app/shared/widgets/animation/celebration_timings.dart';
import 'package:mobile_app/shared/widgets/animation/reveal/reveal_frame.dart';

// The scale an element starts from when its call site has no opinion.
// The value that `ScaleReveal` already ships with, promoted here to the
// entrance every element gets.
const double _kPopFloor = 0.5;

/// `RevealStyle.scalePop` — opacity in from a scale of 0.5.
///
/// What `ScaleReveal` does today, promoted to the entrance EVERY element
/// gets. A call site that brought its own `startScale` keeps it, so the
/// booked image and the video card still pop from exactly where they
/// always did; everything else pops from [_kPopFloor].
///
/// Nothing translates: the pop is the whole entrance, and stacking a
/// slide on top of it would make two beats out of one. No lead-in — a
/// scale across the full 260ms window is plainly readable on its own.
const RevealSpec kScalePopReveal = RevealSpec(
  value: RevealStyle.scalePop,
  leadIn: Duration.zero,
  minDuration: CelebrationTimings.revealDuration,
  frameAt: _frameAt,
);

RevealFrame _frameAt(double t, RevealGeometry geometry) {
  final v = Curves.easeOutQuart.transform(t);
  final floor = geometry.startScale ?? _kPopFloor;
  return RevealFrame(opacity: v, scale: floor + (1 - floor) * v);
}
