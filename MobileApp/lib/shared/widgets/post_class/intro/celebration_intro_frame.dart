import 'package:mobile_app/core/formats/motion_formats.dart';

/// The complete visual state of a celebration intro at one instant.
///
/// Every value of [CelebrationIntro] is expressed as a pure function
/// `double t -> CelebrationIntroFrame`, and one shared figure widget is
/// the only thing that paints one. That split is what makes the
/// timing-and-entrance-only invariant provable rather than promised: a
/// value gets to change these numbers and nothing else. It cannot add an
/// element, drop one, move where the card sits, or reach for data.
///
/// Every default is the SETTLED state, so an intro that leaves a field
/// alone contributes no motion on that axis.
class CelebrationIntroFrame {
  const CelebrationIntroFrame({
    this.heroScale = 1,
    this.heroOpacity = 1,
    this.heroRise = 0,
    this.heroFlip = 0,
    this.heroBlur = 0,
    this.particleSpread = 0,
    this.particleOpacity = 0,
    this.particleSpin = 0,
  });

  /// Uniform scale of the hero figure. Never above 1: the app's motion
  /// law is ease-out only, so nothing may overshoot its settled size.
  final double heroScale;

  final double heroOpacity;

  /// How far BELOW its settled position the hero sits, as a fraction of
  /// the stage's half-height. 0 is settled; 1 is one half-height down.
  /// Never negative — a figure that sails past its landing and comes
  /// back is an overshoot wearing a translation.
  final double heroRise;

  /// Rotation about the vertical axis, in radians. 0 faces the viewer.
  /// Never positive, for the same reason [heroRise] is never negative.
  final double heroFlip;

  /// Vertical gaussian sigma for a motion trail, in reference pixels.
  final double heroBlur;

  /// Particle distance from centre, as a fraction of the stage radius.
  final double particleSpread;

  final double particleOpacity;

  /// Rotation of the whole particle field, in radians.
  final double particleSpin;
}

/// One intro value's whole contract: how long it runs, when the settled
/// content takes over, the particle field it carries, and the pure
/// function that produces its frames.
///
/// The five specs are the only thing that differs between values. Adding
/// a value means adding a spec — there is no seam through which it could
/// reach the card's content.
class CelebrationIntroSpec {
  const CelebrationIntroSpec({
    required this.value,
    required this.total,
    required this.handoff,
    required this.particleRadii,
    required this.frameAt,
  });

  final CelebrationIntro value;

  /// When the intro is over: the figure leaves and `markDone` fires.
  final Duration total;

  /// When the settled content starts revealing. Equal to [total] for
  /// every value except `flipCount`, which hands off mid-flip so the
  /// count-up is already running when the figure lands.
  final Duration handoff;

  /// One entry per particle, each a multiplier on the stage radius.
  /// Empty for the values that carry no particle field, which is what
  /// keeps celebration rationed: a value cannot opt IN to sparkle by
  /// accident, it has to declare the field.
  final List<double> particleRadii;

  final CelebrationIntroFrame Function(double t) frameAt;

  /// True when the settled content and the figure share the stage for a
  /// while, instead of the figure leaving as the content arrives.
  bool get overlaps => handoff < total;
}
