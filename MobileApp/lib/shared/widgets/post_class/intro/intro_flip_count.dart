import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:mobile_app/core/formats/motion_formats.dart';
import 'package:mobile_app/shared/widgets/animation/celebration_timings.dart';
import 'package:mobile_app/shared/widgets/post_class/intro/celebration_intro_frame.dart';

// Composed from `CelebrationTimings`: the flip is the sparkle window,
// the settle is one pulse, the exit is the standard element reveal.
final Duration _kFlip = CelebrationTimings.sparkleWindow;
final Duration _kSettle = CelebrationTimings.pulseDuration;
final Duration _kExit = CelebrationTimings.revealDuration;
final Duration _kTotal = _kFlip + _kSettle + _kExit;

/// The one value that hands off before it finishes. Half way through the
/// flip the settled content starts revealing underneath, so the count-up
/// is already rolling while the figure is still turning.
final Duration _kHandoff = _kFlip ~/ 2;

const double _kExitShrink = 0.3;

/// `CelebrationIntro.flipCount` — the value with the earliest payoff.
///
/// The hero turns in on the vertical axis from edge-on, and the card's
/// figure starts counting mid-turn rather than waiting for the intro to
/// clear. Nothing is added or removed by that overlap: the same settled
/// content arrives, it just arrives while the hero is still moving.
final CelebrationIntroSpec kFlipCountIntro = CelebrationIntroSpec(
  value: CelebrationIntro.flipCount,
  total: _kTotal,
  handoff: _kHandoff,
  particleRadii: const [],
  frameAt: _frameAt,
);

CelebrationIntroFrame _frameAt(double t) {
  final total = _kTotal.inMilliseconds.toDouble();
  final flipEnd = _kFlip.inMilliseconds / total;
  final holdEnd = (_kFlip + _kSettle).inMilliseconds / total;
  final fadeInEnd = _kExit.inMilliseconds / total;

  // Edge-on to face-on, decelerating into square. A quarter turn, so no
  // frame ever shows the mark mirrored, and the rotation approaches zero
  // without passing it.
  final flipE = Curves.easeOutCubic.transform((t / flipEnd).clamp(0.0, 1.0));
  final fadeInE = Curves.easeOut.transform((t / fadeInEnd).clamp(0.0, 1.0));
  final exitT = ((t - holdEnd) / (1 - holdEnd)).clamp(0.0, 1.0);
  final exitE = Curves.easeInQuart.transform(exitT);

  return CelebrationIntroFrame(
    heroScale: 1 - _kExitShrink * exitE,
    heroOpacity: fadeInE * (1 - exitE),
    heroFlip: -(math.pi / 2) * (1 - flipE),
  );
}
