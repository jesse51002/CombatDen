import 'package:mobile_app/core/formats/motion_formats.dart';

/// The complete visual state of ONE element's entrance at one instant.
///
/// Every value of [RevealStyle] is expressed as a pure function
/// `(double t, RevealGeometry) -> RevealFrame`, and one shared figure
/// widget is the only thing that paints one. That split is what makes
/// the timing-and-entrance-only invariant provable rather than promised:
/// a value gets to change these five numbers and nothing else. It cannot
/// add an element, drop one, change where the element lands, or reach
/// for data.
///
/// Every default is the SETTLED state, so a value that leaves a field
/// alone contributes no motion on that axis.
class RevealFrame {
  const RevealFrame({
    this.opacity = 1,
    this.rise = 0,
    this.slide = 0,
    this.scale = 1,
    this.clip = 1,
  });

  final double opacity;

  /// How far BELOW its settled position the element sits, in logical
  /// pixels. 0 is settled. Never negative — an element that sails past
  /// its landing and comes back is an overshoot wearing a translation.
  final double rise;

  /// How far toward the LEADING edge of its settled position the element
  /// sits, in logical pixels. 0 is settled, and never negative, for the
  /// same reason [rise] is never negative. The painter resolves leading
  /// against the ambient [Directionality].
  final double slide;

  /// Uniform scale. Never above 1: the app's motion law is ease-out
  /// only, so nothing may overshoot its settled size.
  final double scale;

  /// Fraction of the element revealed by the wipe, from its leading
  /// edge along its own long axis. 1 is settled (nothing clipped).
  final double clip;

  /// True when this frame is the element exactly as it finally sits.
  bool get isSettled =>
      opacity == 1 && rise == 0 && slide == 0 && scale == 1 && clip == 1;
}

/// The geometry ONE call site brings to its own entrance.
///
/// These are the two knobs the shipped widgets already expose —
/// `StaggeredReveal.offset` and `ScaleReveal.startScale` — so the pair
/// carries the whole difference between the two shipped entrances. That
/// is why [RevealStyle.fadeUp] can reproduce BOTH of them verbatim from
/// one frame function: the widget says which axis it moves on, the value
/// says how.
class RevealGeometry {
  const RevealGeometry({this.translate, this.startScale});

  /// The call site's own translate distance in logical pixels, when it
  /// has one (`StaggeredReveal.offset`). Null when the call site does
  /// not translate at all (`ScaleReveal`).
  final double? translate;

  /// The call site's own starting scale (`ScaleReveal.startScale`).
  /// Null when the call site does not scale (`StaggeredReveal`).
  final double? startScale;

  /// Whether this call site wants to be displaced at all. `offset: 0`
  /// — the wins trophy, which has to stay registered with the sparkle
  /// burst behind it, and the rewards carousel — says no, and EVERY
  /// value honours it. A format changes how an element enters; it does
  /// not get to overrule a call site that asked to hold its position.
  bool get displaces => translate != 0;
}

/// One reveal value's whole contract: how long it holds before it
/// starts, the shortest run it is legible in, and the pure function that
/// produces its frames.
///
/// The four specs are the only thing that differs between values. Adding
/// a value means adding a spec — there is no seam through which it could
/// reach the element it is revealing.
class RevealSpec {
  const RevealSpec({
    required this.value,
    required this.leadIn,
    required this.minDuration,
    required this.frameAt,
  });

  final RevealStyle value;

  /// Held still before the motion starts, ON TOP of the call site's own
  /// `delay`. It exists because a short entrance fired the instant an
  /// element mounts reads as a glitch, not a moment: the eye needs a
  /// beat to register that something is about to happen. Uniform across
  /// every element, so the stagger the call sites authored is shifted
  /// wholesale and never reordered.
  final Duration leadIn;

  /// The floor on the motion's own run. A call site asking for longer
  /// (the booked image's 720ms, the video card's 480ms) keeps its
  /// length; one asking for less is raised to this, because an entrance
  /// shorter than this is a cut rather than something a viewer can read.
  /// See [kRevealLegibilityFloor].
  final Duration minDuration;

  final RevealFrame Function(double t, RevealGeometry geometry) frameAt;

  /// The run this value actually gets for a call site that asked for
  /// [requested].
  Duration runFor(Duration requested) =>
      requested < minDuration ? minDuration : requested;

  /// Lead-in plus run: the whole entrance, measured from the moment the
  /// call site's own `delay` elapses.
  Duration totalFor(Duration requested) => leadIn + runFor(requested);
}

/// The shortest run in which an entrance is still PROCESSABLE.
///
/// Under roughly a quarter of a second a transition stops reading as a
/// transition and reads as a cut — the element is simply somewhere else
/// before the viewer has registered that it moved. Values are free to
/// differ in length; they are not free to be too fast to see. The upper
/// bound is the app's existing motion law,
/// `MotionSpec.elementDurationCeiling` (300ms), so every value's own run
/// lives in a narrow 240–300ms band and any extra weight comes from
/// [RevealSpec.leadIn] and from stagger.
const Duration kRevealLegibilityFloor = Duration(milliseconds: 240);
