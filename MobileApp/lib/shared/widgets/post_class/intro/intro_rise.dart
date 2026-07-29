import 'package:flutter/animation.dart';
import 'package:mobile_app/core/formats/motion_formats.dart';
import 'package:mobile_app/shared/widgets/animation/celebration_timings.dart';
import 'package:mobile_app/shared/widgets/post_class/intro/celebration_intro_frame.dart';

// The exit is `CelebrationTimings`; the beats before it are this
// intro's own timing math, per CLAUDE.md's `_k` carve-out.
//
// The climb IS the run-up here — long and decelerating, so the figure
// is legible the whole way up instead of snapping into place. The short
// opening beat in front of it mirrors `orbit`: a moment of empty canvas
// so the arrival registers as an arrival.
const Duration _kDelay = Duration(milliseconds: 300);
const Duration _kClimb = Duration(milliseconds: 1200);
const Duration _kHold = Duration(milliseconds: 700);
final Duration _kExit = CelebrationTimings.revealDuration;

final Duration _kTotal = _kDelay + _kClimb + _kHold + _kExit;

/// How long the figure takes to fade up once it starts climbing. Slower
/// than a standard element reveal on purpose: it fades in while it is
/// still travelling, so nothing is fully present before the run-up is.
final Duration _kFadeIn = CelebrationTimings.revealDuration * 2;

/// Peak trail sigma, in reference pixels. Decays to zero as the figure
/// lands, so the blur reads as speed rather than as an out-of-focus
/// image sitting on the card.
const double _kTrailBlur = 16;
const double _kExitShrink = 0.3;

/// `CelebrationIntro.rise` — the calm value.
///
/// The hero climbs from below the stage with a vertical trail behind
/// it, sharpening as it decelerates, and settles. No particles at all:
/// this is the value for a tenant that wants the post-class moment to
/// land without any scatter on screen.
final CelebrationIntroSpec kRiseIntro = CelebrationIntroSpec(
  value: CelebrationIntro.rise,
  total: _kTotal,
  particleRadii: const [],
  frameAt: _frameAt,
);

CelebrationIntroFrame _frameAt(double t) {
  final ms = t * _kTotal.inMilliseconds;
  final climbStart = _kDelay.inMilliseconds.toDouble();
  final exitStart =
      climbStart + _kClimb.inMilliseconds + _kHold.inMilliseconds;

  // One monotone ease-out climb: the figure decelerates into its
  // landing and stops there. It never passes the landing and comes back.
  final climbE = Curves.easeOutQuart.transform(
    ((ms - climbStart) / _kClimb.inMilliseconds).clamp(0.0, 1.0),
  );
  final fadeInE = Curves.easeOut.transform(
    ((ms - climbStart) / _kFadeIn.inMilliseconds).clamp(0.0, 1.0),
  );
  final exitE = Curves.easeInQuart.transform(
    ((ms - exitStart) / _kExit.inMilliseconds).clamp(0.0, 1.0),
  );

  return CelebrationIntroFrame(
    heroScale: 1 - _kExitShrink * exitE,
    heroOpacity: fadeInE * (1 - exitE),
    heroRise: 1 - climbE,
    heroBlur: _kTrailBlur * (1 - climbE),
  );
}
