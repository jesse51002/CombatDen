import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:mobile_app/core/formats/motion_formats.dart';
import 'package:mobile_app/shared/widgets/post_class/intro/celebration_intro_frame.dart';

// The shipped streak intro's beats, carried over verbatim from the
// hand-rolled `_StreakOrbit` this replaced. File-scoped per CLAUDE.md's
// `_k` carve-out: these are one intro's timing math, not app tokens.
const Duration _kDelay = Duration(milliseconds: 500);
// The mini-icon ring expands then immediately collapses — a quick
// out-and-back pulse before the big icon pop.
const Duration _kRingGrow = Duration(milliseconds: 600);
const Duration _kRingCollapse = Duration(milliseconds: 500);
// After the ring collapses the hero pops up, holds, then leaves into the
// stats cascade.
const Duration _kIconPop = Duration(milliseconds: 400);
const Duration _kIconHold = Duration(milliseconds: 800);
const Duration _kIconExit = Duration(milliseconds: 250);
const int _kOrbitCount = 8;
const double _kSpinTurns = 1.6;
const double _kExitShrink = 0.3;

// Top-level `final` because Duration's `+` is not a const operator.
final Duration _kTotal =
    _kDelay + _kRingGrow + _kRingCollapse + _kIconPop + _kIconHold + _kIconExit;

/// `CelebrationIntro.orbit` — the value that ships.
///
/// A ring of small marks expands out from centre, spinning the whole
/// time, then collapses back to nothing; the hero pops up in the space
/// it left, holds, and fades into the stats cascade.
///
/// One deliberate difference from the hand-rolled original: the hero's
/// pop used an anticipation curve that carried the figure past its
/// settled size before easing down. The app's motion law is ease-out
/// only, and the invariants gate proves no value overshoots, so the pop
/// runs on ease-out-quart. Every other number here is the original's.
final CelebrationIntroSpec kOrbitIntro = CelebrationIntroSpec(
  value: CelebrationIntro.orbit,
  total: _kTotal,
  particleRadii: List<double>.filled(_kOrbitCount, 1),
  frameAt: _frameAt,
);

CelebrationIntroFrame _frameAt(double t) {
  final total = _kTotal.inMilliseconds.toDouble();
  final delayEnd = _kDelay.inMilliseconds / total;
  final ringGrowEnd = (_kDelay + _kRingGrow).inMilliseconds / total;
  final ringEnd =
      (_kDelay + _kRingGrow + _kRingCollapse).inMilliseconds / total;
  final popEnd =
      (_kDelay + _kRingGrow + _kRingCollapse + _kIconPop).inMilliseconds /
      total;
  final holdEnd =
      (_kDelay + _kRingGrow + _kRingCollapse + _kIconPop + _kIconHold)
          .inMilliseconds /
      total;

  // Ring: expand, then collapse to centre. No hold between the two.
  final growT = ((t - delayEnd) / (ringGrowEnd - delayEnd)).clamp(0.0, 1.0);
  final collapseT = ((t - ringGrowEnd) / (ringEnd - ringGrowEnd)).clamp(
    0.0,
    1.0,
  );
  final expandE = Curves.easeOutQuart.transform(growT);
  final collapseE = Curves.easeInQuart.transform(collapseT);
  // 0 -> 1 (grow), 1 -> 0 (collapse). Doubles as the ring's opacity, so
  // the marks are invisible before they leave centre and after they
  // return to it.
  final spread = expandE * (1 - collapseE);

  // Hero: pops only once the ring is gone, holds, then leaves.
  final popT = ((t - ringEnd) / (popEnd - ringEnd)).clamp(0.0, 1.0);
  final exitT = ((t - holdEnd) / (1 - holdEnd)).clamp(0.0, 1.0);
  final exitE = Curves.easeInQuart.transform(exitT);

  return CelebrationIntroFrame(
    heroScale:
        Curves.easeOutQuart.transform(popT) * (1 - _kExitShrink * exitE),
    heroOpacity: Curves.easeOut.transform(popT) * (1 - exitE),
    particleSpread: spread,
    particleOpacity: spread,
    particleSpin: t * 2 * math.pi * _kSpinTurns,
  );
}
