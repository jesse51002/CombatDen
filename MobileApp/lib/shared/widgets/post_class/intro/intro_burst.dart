import 'package:flutter/animation.dart';
import 'package:mobile_app/core/formats/motion_formats.dart';
import 'package:mobile_app/shared/widgets/animation/celebration_timings.dart';
import 'package:mobile_app/shared/widgets/post_class/intro/celebration_intro_frame.dart';

// The fire and its fade are `CelebrationTimings`; the beats around them
// are this intro's own timing math, per CLAUDE.md's `_k` carve-out.
//
// The gather is the load-bearing beat. A burst fired the instant the
// card mounts is over before the eye finds it — it reads as a glitch,
// not a moment. So the marks fade in slightly out from centre and draw
// INWARD first: a real run-up that says something is about to happen,
// rather than dead time where nothing moves.
const Duration _kDelay = Duration(milliseconds: 300);
const Duration _kGather = Duration(milliseconds: 700);
final Duration _kFire = CelebrationTimings.sparkleWindow;
const Duration _kHold = Duration(milliseconds: 500);
final Duration _kExit = CelebrationTimings.revealDuration;

final Duration _kTotal = _kDelay + _kGather + _kFire + _kHold + _kExit;

// Where the marks sit when they first appear, and how far in they draw
// before firing, as fractions of the stage radius.
const double _kGatherFrom = 0.34;
const double _kGatherTo = 0.12;

// Uneven radii so the marks read as a scatter rather than a ring —
// there is no rotation to break the circle up here.
const List<double> _kRadii = [
  1.0,
  0.72,
  0.94,
  0.61,
  0.86,
  0.78,
  1.0,
  0.67,
  0.90,
  0.58,
  0.82,
  0.74,
];
const double _kExitShrink = 0.3;

/// `CelebrationIntro.burst` — the punchiest value.
///
/// The marks gather inward around the hero, then fire outward once and
/// fade where they land. No ring, no rotation, no return trip. Still the
/// shortest intro, but the payoff now has a run-up in front of it and a
/// beat behind it, so there is time to read what happened.
final CelebrationIntroSpec kBurstIntro = CelebrationIntroSpec(
  value: CelebrationIntro.burst,
  total: _kTotal,
  particleRadii: _kRadii,
  frameAt: _frameAt,
);

CelebrationIntroFrame _frameAt(double t) {
  final ms = t * _kTotal.inMilliseconds;
  final gatherStart = _kDelay.inMilliseconds.toDouble();
  final fireStart = gatherStart + _kGather.inMilliseconds;
  final fireEnd = fireStart + _kFire.inMilliseconds;
  final exitStart = fireEnd + _kHold.inMilliseconds;
  final fadeStart = fireEnd - CelebrationTimings.sparkleFade.inMilliseconds;

  final gatherT = ((ms - gatherStart) / _kGather.inMilliseconds).clamp(
    0.0,
    1.0,
  );
  final fireT = ((ms - fireStart) / _kFire.inMilliseconds).clamp(0.0, 1.0);
  final exitT = ((ms - exitStart) / _kExit.inMilliseconds).clamp(0.0, 1.0);
  final exitE = Curves.easeInQuart.transform(exitT);

  // The marks draw in on an ease-IN — still accelerating when the fire
  // takes over, so the turn outward reads as a release — then out on
  // ease-out, decelerating into where they land.
  final drawnIn = Curves.easeInQuart.transform(gatherT);
  final spread = ms >= fireStart
      ? _kGatherTo + (1 - _kGatherTo) * Curves.easeOutQuart.transform(fireT)
      : _kGatherFrom + (_kGatherTo - _kGatherFrom) * drawnIn;

  // Opacity: up across the gather, held through the fire, gone by the
  // time the marks land.
  final fadeIn = Curves.easeOut.transform(gatherT);
  final fadeOut = Curves.easeOut.transform(
    ((ms - fadeStart) / CelebrationTimings.sparkleFade.inMilliseconds).clamp(
      0.0,
      1.0,
    ),
  );

  // The hero arrives with the gather, so the marks converge on
  // something rather than on a bare canvas.
  return CelebrationIntroFrame(
    heroScale:
        Curves.easeOutQuart.transform(gatherT) * (1 - _kExitShrink * exitE),
    heroOpacity: Curves.easeOut.transform(gatherT) * (1 - exitE),
    particleSpread: spread,
    particleOpacity: fadeIn * (1 - fadeOut),
  );
}
