import 'package:flutter/animation.dart';
import 'package:mobile_app/core/formats/motion_formats.dart';
import 'package:mobile_app/shared/widgets/animation/celebration_timings.dart';
import 'package:mobile_app/shared/widgets/animation/reveal/reveal_frame.dart';

/// `RevealStyle.fadeUp` — the value that ships.
///
/// Opacity in on ease-out-quart while the element rises the last few
/// pixels into place. It reproduces BOTH shipped entrances exactly,
/// because the difference between them was never the curve — it was the
/// axis each call site brought:
///
/// * `StaggeredReveal` brings `translate` (12px by default) and no
///   scale, so this is opacity + a 12px upward translate.
/// * `ScaleReveal` brings `startScale` (0.5) and no translate, so this
///   is opacity + a scale from 0.5.
///
/// No lead-in and the shipped 260ms run: an un-opted-in tenant sees the
/// app exactly as it animates today, down to the frame.
const RevealSpec kFadeUpReveal = RevealSpec(
  value: RevealStyle.fadeUp,
  leadIn: Duration.zero,
  minDuration: CelebrationTimings.revealDuration,
  frameAt: _frameAt,
);

RevealFrame _frameAt(double t, RevealGeometry geometry) {
  final v = Curves.easeOutQuart.transform(t);
  final startScale = geometry.startScale ?? 1.0;
  return RevealFrame(
    opacity: v,
    rise: (geometry.translate ?? 0) * (1 - v),
    scale: startScale + (1 - startScale) * v,
  );
}
