import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:mobile_app/core/formats/motion_formats.dart';
import 'package:mobile_app/shared/widgets/animation/celebration_timings.dart';
import 'package:mobile_app/shared/widgets/post_class/intro/celebration_intro_frame.dart';

// The turn is this intro's own timing math, per CLAUDE.md's `_k`
// carve-out. It is slow on purpose: a quarter turn is a small amount of
// change, and at speed it reads as a flicker rather than as a figure
// turning to face you.
const Duration _kDelay = Duration(milliseconds: 300);
const Duration _kFlip = Duration(milliseconds: 1200);
// The landed figure gets a real beat facing you before it leaves, the
// same shape as `orbit`'s hold: the turn is the point, so it has to
// finish being a turn before the card moves on.
const Duration _kHold = Duration(milliseconds: 700);
const Duration _kExit = Duration(milliseconds: 300);

final Duration _kTotal = _kDelay + _kFlip + _kHold + _kExit;

/// Matches `rise`: the figure fades up while it is still turning, so it
/// is never fully present before the run-up is.
final Duration _kFadeIn = CelebrationTimings.revealDuration * 2;

const double _kExitShrink = 0.3;

/// `CelebrationIntro.flipCount` — the deliberate one.
///
/// The hero turns in on the vertical axis from edge-on, holds facing
/// you, and leaves; then the card settles and its figure counts up.
///
/// An earlier draft started the count mid-turn, so the roll and the
/// flip overlapped. On a real screen that did not read as one composed
/// moment — it read as the card giving up on its own animation and
/// jumping ahead. The intro owns the stage until it is finished, like
/// every other value.
final CelebrationIntroSpec kFlipCountIntro = CelebrationIntroSpec(
  value: CelebrationIntro.flipCount,
  total: _kTotal,
  particleRadii: const [],
  frameAt: _frameAt,
);

CelebrationIntroFrame _frameAt(double t) {
  final ms = t * _kTotal.inMilliseconds;
  final flipStart = _kDelay.inMilliseconds.toDouble();
  final exitStart = flipStart + _kFlip.inMilliseconds + _kHold.inMilliseconds;

  // Edge-on to face-on, decelerating into square. A quarter turn, so no
  // frame ever shows the mark mirrored, and the rotation approaches
  // zero without passing it.
  final flipE = Curves.easeOutCubic.transform(
    ((ms - flipStart) / _kFlip.inMilliseconds).clamp(0.0, 1.0),
  );
  final fadeInE = Curves.easeOut.transform(
    ((ms - flipStart) / _kFadeIn.inMilliseconds).clamp(0.0, 1.0),
  );
  final exitE = Curves.easeInQuart.transform(
    ((ms - exitStart) / _kExit.inMilliseconds).clamp(0.0, 1.0),
  );

  return CelebrationIntroFrame(
    heroScale: 1 - _kExitShrink * exitE,
    heroOpacity: fadeInE * (1 - exitE),
    heroFlip: -(math.pi / 2) * (1 - flipE),
  );
}
