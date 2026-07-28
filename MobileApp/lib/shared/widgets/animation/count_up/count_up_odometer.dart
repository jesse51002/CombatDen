import 'package:flutter/animation.dart';
import 'package:mobile_app/core/formats/motion_formats.dart';
import 'package:mobile_app/shared/widgets/animation/count_up/count_up_frame.dart';

/// `CountUpStyle.odometer` — the value that ships.
///
/// The standard slot-counter reel: one vertical strip per digit
/// position, each strip listing every integer that digit will pass
/// through, translated by `translateY` and clipped to a one-digit-tall
/// window. The visible digit slides in from below and the previous one
/// slides up out the top — no widget swap, no fade. The steep
/// ease-out-exp curve shapes the spin: fast scroll up front, long slow
/// landing on the final digits.
///
/// **This value is reproduced beat for beat and must stay that way.** It
/// is the parse fallback, so an unbranded build and every tenant without
/// the slot render through it — changing its curve, its length, or its
/// start would change what ships for all of them. That is also why it
/// alone carries no lead-in hold: the shipped roll begins the instant the
/// figure mounts, and its own 1400ms window already gives the eye ~865ms
/// of visibly moving digits to land on and read.
const CountUpSpec kOdometerCountUp = CountUpSpec(
  value: CountUpStyle.odometer,
  scale: 1,
  reeled: true,
  hasArc: false,
  frameAt: _frameAt,
);

CountUpFrame _frameAt(double t) =>
    CountUpFrame(progress: Curves.easeOutExpo.transform(t.clamp(0.0, 1.0)));
