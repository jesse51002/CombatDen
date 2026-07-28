import 'package:flutter/animation.dart';
import 'package:mobile_app/core/formats/motion_formats.dart';
import 'package:mobile_app/shared/widgets/animation/reveal/reveal_frame.dart';

// The longest lead-in of the four. A wipe has no transform and no fade —
// the element simply materialises — so without a held beat in front of
// it the eye reads it as a flicker rather than as something arriving.
const Duration _kLeadIn = Duration(milliseconds: 90);

// The full element ceiling. A wipe is the value most at risk of being
// over before it is seen, so it takes every millisecond the app's motion
// law allows.
const Duration _kMinDuration = Duration(milliseconds: 300);

/// `RevealStyle.maskWipe` — the element is uncovered by a clip that
/// sweeps along its own long axis.
///
/// The point of this value is that NOTHING is transformed: no scale, no
/// translate, no opacity ramp. Text is therefore rendered at exactly its
/// final size and position for every frame it is visible, so it stays
/// pin-sharp instead of resampling through a fractional transform the
/// way a fade-and-scale entrance does.
///
/// The sweep runs on ease-out-SINE rather than the app's usual
/// ease-out-quart. Quart is heavily front-loaded, which makes an
/// edge-travel look like a snap; sine keeps the leading edge moving at a
/// readable rate for the whole run. It is still an ease-out, so the
/// motion law holds.
const RevealSpec kMaskWipeReveal = RevealSpec(
  value: RevealStyle.maskWipe,
  leadIn: _kLeadIn,
  minDuration: _kMinDuration,
  frameAt: _frameAt,
);

RevealFrame _frameAt(double t, RevealGeometry geometry) =>
    RevealFrame(clip: Curves.easeOutSine.transform(t));
