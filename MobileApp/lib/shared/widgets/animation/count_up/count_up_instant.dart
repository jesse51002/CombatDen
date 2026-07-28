import 'package:mobile_app/core/formats/motion_formats.dart';
import 'package:mobile_app/shared/widgets/animation/count_up/count_up_frame.dart';

/// `CountUpStyle.instant` — the figure is simply there.
///
/// The only value exempt from the legibility floor the invariants gate
/// holds the others to, and deliberately so: "no animation" and "an
/// animation too fast to read" are different things, and this is the
/// first. It is not padded with a hold or a run-up, because there is
/// nothing for a lead-in to lead into.
///
/// The entrance is still there — it just belongs to the surrounding
/// reveal (`StaggeredReveal` at every call site today), which is the
/// tenant's `reveal_style`, not this slot's business.
const CountUpSpec kInstantCountUp = CountUpSpec(
  value: CountUpStyle.instant,
  scale: 0,
  reeled: false,
  hasArc: false,
  frameAt: _frameAt,
);

CountUpFrame _frameAt(double t) => const CountUpFrame();
