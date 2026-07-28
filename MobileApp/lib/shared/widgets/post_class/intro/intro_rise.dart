import 'package:flutter/animation.dart';
import 'package:mobile_app/core/formats/motion_formats.dart';
import 'package:mobile_app/shared/widgets/animation/celebration_timings.dart';
import 'package:mobile_app/shared/widgets/post_class/intro/celebration_intro_frame.dart';

// Composed from `CelebrationTimings`: the climb is the sparkle window,
// the settle is one pulse, the exit is the standard element reveal.
final Duration _kClimb = CelebrationTimings.sparkleWindow;
final Duration _kSettle = CelebrationTimings.pulseDuration;
final Duration _kExit = CelebrationTimings.revealDuration;
final Duration _kTotal = _kClimb + _kSettle + _kExit;

/// Peak trail sigma, in reference pixels. Decays to zero as the figure
/// lands, so the blur reads as speed rather than as an out-of-focus
/// image sitting on the card.
const double _kTrailBlur = 16;
const double _kExitShrink = 0.3;

/// `CelebrationIntro.rise` — the calm value.
///
/// The hero climbs from below the stage with a vertical trail behind it,
/// sharpening as it decelerates, and settles. No particles at all: this
/// is the value for a tenant that wants the post-class moment to land
/// without any scatter on screen.
final CelebrationIntroSpec kRiseIntro = CelebrationIntroSpec(
  value: CelebrationIntro.rise,
  total: _kTotal,
  handoff: _kTotal,
  particleRadii: const [],
  frameAt: _frameAt,
);

CelebrationIntroFrame _frameAt(double t) {
  final total = _kTotal.inMilliseconds.toDouble();
  final climbEnd = _kClimb.inMilliseconds / total;
  final holdEnd = (_kClimb + _kSettle).inMilliseconds / total;
  final fadeInEnd = _kExit.inMilliseconds / total;

  // One monotone ease-out climb: the figure decelerates into its landing
  // and stops there. It never passes the landing and comes back.
  final climbE = Curves.easeOutQuart.transform(
    (t / climbEnd).clamp(0.0, 1.0),
  );
  final fadeInE = Curves.easeOut.transform(
    (t / fadeInEnd).clamp(0.0, 1.0),
  );
  final exitT = ((t - holdEnd) / (1 - holdEnd)).clamp(0.0, 1.0);
  final exitE = Curves.easeInQuart.transform(exitT);

  return CelebrationIntroFrame(
    heroScale: 1 - _kExitShrink * exitE,
    heroOpacity: fadeInE * (1 - exitE),
    heroRise: 1 - climbE,
    heroBlur: _kTrailBlur * (1 - climbE),
  );
}
