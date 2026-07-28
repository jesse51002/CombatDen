import 'package:flutter/animation.dart';
import 'package:mobile_app/core/formats/motion_formats.dart';
import 'package:mobile_app/shared/widgets/animation/celebration_timings.dart';
import 'package:mobile_app/shared/widgets/post_class/intro/celebration_intro_frame.dart';

// Composed from `CelebrationTimings` rather than invented: the particle
// flight is the sparkle window, the fade is the sparkle fade, and the
// hero's entry and exit are the standard element reveal.
final Duration _kFly = CelebrationTimings.sparkleWindow;
final Duration _kExit = CelebrationTimings.revealDuration;
final Duration _kTotal = _kFly + _kExit;

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
const double _kParticleFadeIn = 0.12;
const double _kExitShrink = 0.3;

/// `CelebrationIntro.burst` — the shortest value.
///
/// The marks fire outward from the hero exactly once and fade where they
/// land. No ring, no rotation, no return trip: the particle field is
/// spent by the time the hero leaves, which is what keeps this at a
/// third of `orbit`'s length without feeling clipped.
final CelebrationIntroSpec kBurstIntro = CelebrationIntroSpec(
  value: CelebrationIntro.burst,
  total: _kTotal,
  handoff: _kTotal,
  particleRadii: _kRadii,
  frameAt: _frameAt,
);

CelebrationIntroFrame _frameAt(double t) {
  final total = _kTotal.inMilliseconds.toDouble();
  final flyEnd = _kFly.inMilliseconds / total;
  final fadeStart =
      (_kFly - CelebrationTimings.sparkleFade).inMilliseconds / total;

  // Hero: in on the standard reveal, then out over the tail.
  final popT = (t / (_kExit.inMilliseconds / total)).clamp(0.0, 1.0);
  final exitT = ((t - flyEnd) / (1 - flyEnd)).clamp(0.0, 1.0);
  final exitE = Curves.easeInQuart.transform(exitT);

  // Particles: one outward throw on ease-out-quart (they decelerate into
  // where they land, they never spring back), holding opacity until the
  // last slice of the window.
  final spread = Curves.easeOutQuart.transform((t / flyEnd).clamp(0.0, 1.0));
  final fadeInE = Curves.easeOut.transform(
    (t / _kParticleFadeIn).clamp(0.0, 1.0),
  );
  final fadeOutE = Curves.easeOut.transform(
    ((t - fadeStart) / (flyEnd - fadeStart)).clamp(0.0, 1.0),
  );

  return CelebrationIntroFrame(
    heroScale:
        Curves.easeOutQuart.transform(popT) * (1 - _kExitShrink * exitE),
    heroOpacity: Curves.easeOut.transform(popT) * (1 - exitE),
    particleSpread: spread,
    particleOpacity: fadeInE * (1 - fadeOutE),
  );
}
