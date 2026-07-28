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
const Duration _kHold = Duration(milliseconds: 200);
// A long, gentle fade rather than a snap: the figure is dissolving over
// a count-up that is already rolling, so this beat is a cross-fade.
const Duration _kExit = Duration(milliseconds: 800);

final Duration _kTotal = _kDelay + _kFlip + _kHold + _kExit;

/// The one value that hands off before it finishes. Half way through
/// the turn the settled content starts revealing underneath, so the
/// count-up is already rolling while the figure is still moving.
final Duration _kHandoff = _kDelay + _kFlip ~/ 2;

/// Matches `rise`: the figure fades up while it is still turning, so it
/// is never fully present before the run-up is.
final Duration _kFadeIn = CelebrationTimings.revealDuration * 2;

const double _kExitShrink = 0.3;

/// `CelebrationIntro.flipCount` — the value with the earliest payoff.
///
/// The hero turns in on the vertical axis from edge-on, and the card's
/// figure starts counting mid-turn rather than waiting for the intro to
/// clear. Nothing is added or removed by that overlap: the same settled
/// content arrives, in the same place, while the hero is still moving.
final CelebrationIntroSpec kFlipCountIntro = CelebrationIntroSpec(
  value: CelebrationIntro.flipCount,
  total: _kTotal,
  handoff: _kHandoff,
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
  // Ease-OUT on the way out too, so the figure clears the count-up
  // early in the beat instead of sitting on top of it and then
  // vanishing.
  final exitE = Curves.easeOut.transform(
    ((ms - exitStart) / _kExit.inMilliseconds).clamp(0.0, 1.0),
  );

  return CelebrationIntroFrame(
    heroScale: 1 - _kExitShrink * exitE,
    heroOpacity: fadeInE * (1 - exitE),
    heroFlip: -(math.pi / 2) * (1 - flipE),
  );
}
