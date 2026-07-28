import 'package:flutter/animation.dart';
import 'package:mobile_app/core/formats/motion_formats.dart';
import 'package:mobile_app/shared/widgets/animation/reveal/reveal_frame.dart';

// How far in from the leading edge an element starts. Wider than the
// 12px `fadeUp` nudge because this one is meant to READ as travel, not
// as a settle. File-scoped per CLAUDE.md's `_k` carve-out: one value's
// motion math, not an app token.
const double _kSlideDistance = 28;

// The fraction of the run over which opacity reaches 1. Short on
// purpose: "opacity held high" means the element is solid for most of
// its journey, so what the eye follows is the travel and not a fade.
const double _kFadeFraction = 0.35;

// A beat of stillness before the travel starts, so the element registers
// as present before it moves.
const Duration _kLeadIn = Duration(milliseconds: 60);

// Slightly longer than the shipped 260ms: a horizontal traverse needs
// more time to read as a traverse than a 12px settle does. Still inside
// the app's 300ms element ceiling.
const Duration _kMinDuration = Duration(milliseconds: 280);

/// `RevealStyle.slideIn` — the element travels in from the leading edge
/// with its opacity held high.
///
/// "Leading" is resolved against the ambient `Directionality` by the
/// painter, so an RTL locale gets the mirror of this without the value
/// knowing anything about it.
///
/// A call site that asked not to be displaced (`offset: 0`) is not
/// displaced here either — it just fades. Nothing scales: a slide plus a
/// pop is two entrances, and a format gets one.
const RevealSpec kSlideInReveal = RevealSpec(
  value: RevealStyle.slideIn,
  leadIn: _kLeadIn,
  minDuration: _kMinDuration,
  frameAt: _frameAt,
);

RevealFrame _frameAt(double t, RevealGeometry geometry) {
  final travel = Curves.easeOutQuart.transform(t);
  final fade = Curves.easeOutQuart.transform(
    (t / _kFadeFraction).clamp(0.0, 1.0),
  );
  return RevealFrame(
    opacity: fade,
    slide: (geometry.displaces ? _kSlideDistance : 0) * (1 - travel),
  );
}
