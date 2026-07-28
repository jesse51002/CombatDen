import 'package:mobile_app/core/formats/motion_formats.dart';
import 'package:mobile_app/shared/widgets/post_class/intro/celebration_intro_frame.dart';

/// `CelebrationIntro.none` — the card arrives settled.
///
/// Zero length, so the stage never mounts a figure and hands straight to
/// the settled content, whose own reveals still cascade. It finishes on
/// the first frame: a card that never finishes is a card whose CTA never
/// appears, which is a dead end rather than a calm intro.
const CelebrationIntroSpec kNoneIntro = CelebrationIntroSpec(
  value: CelebrationIntro.none,
  total: Duration.zero,
  handoff: Duration.zero,
  particleRadii: [],
  frameAt: _frameAt,
);

/// Never painted (the figure is not mounted for a zero-length intro),
/// but still the settled state, so the invariants gate can sample every
/// value's frames through one code path.
CelebrationIntroFrame _frameAt(double t) =>
    const CelebrationIntroFrame(heroOpacity: 0);
