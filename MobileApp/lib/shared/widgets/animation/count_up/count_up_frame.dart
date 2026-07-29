import 'package:mobile_app/core/formats/motion_formats.dart';

/// The complete visual state of a count-up at one instant.
///
/// Every value of [CountUpStyle] is expressed as a pure function
/// `double t -> CountUpFrame`, and one shared figure widget is the only
/// thing that paints one. That split is what makes the
/// timing-and-entrance-only invariant provable rather than promised: a
/// value gets to change these numbers and nothing else. It cannot change
/// the figure's final string, its style, its prefix or suffix, the size
/// of the box it occupies, or reach for data.
///
/// Every default is the SETTLED state, so a value that leaves a field
/// alone contributes no motion on that axis.
class CountUpFrame {
  const CountUpFrame({
    this.progress = 1,
    this.arcSweep = 1,
    this.arcOpacity = 0,
  });

  /// Fraction of the target the figure currently shows, 0..1. Never
  /// above 1 and never decreasing: an earned figure that sails past its
  /// value and comes back is an overshoot wearing a number.
  final double progress;

  /// How far the arc has swept, 0..1. Only the values that declare an
  /// arc render it — see [CountUpSpec.hasArc].
  final double arcSweep;

  /// Arc visibility. 0 at rest for every value, which is what keeps the
  /// settled figure identical across values: the arc is a transient the
  /// motion owns, never part of what the surface says.
  final double arcOpacity;

  /// The whole number on screen at this instant.
  ///
  /// One derivation, shared by every value, so "which number is
  /// showing" cannot diverge between them — only when it gets there.
  int displayedValue(int target) => (progress * target).round();
}

/// One count-up value's whole contract: how long it runs relative to the
/// reference duration, whether its digits ride reels, whether it carries
/// an arc, and the pure function that produces its frames.
///
/// The four specs are the only thing that differs between values. Adding
/// a value means adding a spec — there is no seam through which it could
/// reach the figure's text.
class CountUpSpec {
  const CountUpSpec({
    required this.value,
    required this.scale,
    required this.reeled,
    required this.hasArc,
    required this.frameAt,
  });

  final CountUpStyle value;

  /// Total run length as a multiple of the caller's reference duration
  /// (`CountUpText.duration`, `CelebrationTimings.countUpDuration` by
  /// default). Values are free to differ in length; what they may not do
  /// is resolve faster than a person can watch the figure arrive and read
  /// where it landed — the invariants gate holds each one to a floor.
  ///
  /// Zero means the value does not animate at all.
  final double scale;

  /// Whether each digit position rides a continuous vertical reel
  /// (`odometer`) or simply shows the digit the counter is on. Declared
  /// rather than inferred so the gate can assert that exactly one value
  /// pays for the reels.
  final bool reeled;

  /// Whether the value draws a sweeping arc beneath the figure. Empty
  /// for the values that carry none, which is what keeps celebration
  /// rationed: a value cannot opt IN to decoration by accident, it has
  /// to declare it.
  final bool hasArc;

  final CountUpFrame Function(double t) frameAt;

  /// True when the figure arrives at its final value and there is
  /// nothing to play. "No animation" is a legitimate value; "an
  /// animation too fast to read" is not.
  bool get isInstant => scale == 0;

  Duration totalFor(Duration reference) => reference * scale;
}
