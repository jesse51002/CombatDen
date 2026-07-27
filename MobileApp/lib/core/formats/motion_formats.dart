/// The motion format enums: one personality that resolves the whole
/// timing set, plus five per-surface overrides for the surfaces that
/// carry brand weight.
///
/// Motion is a TOKEN, not a layout. It must not be able to break any
/// arrangement, so these enums touch timing and entrance only — never
/// which elements exist or where they sit.
///
/// As with the layout enums, the first value of each is what ships
/// today and is the parse fallback, so an unbranded build and a tenant
/// missing the slot both render exactly the current app.
library;

import 'package:mobile_app/core/formats/format_parse.dart';

/// Resolves the whole timing set. Every surface inherits from this
/// unless explicitly overridden.
///
/// No value uses an overshoot or elastic curve. The app's motion law is
/// ease-out only (see `MobileApp/CLAUDE.md` and `PRODUCT.md`), so a
/// "hype" built on `easeOutBack` would be a brand change smuggled in as
/// a token. Energy comes from stagger density instead.
enum MotionPersonality {
  /// 260ms / easeOutQuart / 90ms stagger. Reproduces
  /// `CelebrationTimings` exactly.
  standard,

  /// Slower, softer, no decorative particles.
  calm,

  /// Shorter and denser. Energy from stagger, never from bounce.
  hype,

  /// Long and deliberate. Capped by the app's element ceiling — see
  /// [MotionSpec.elementDurationCeiling].
  cinematic;

  static MotionPersonality fromWire(String? wire) =>
      parseFormat(values, wire, MotionPersonality.standard);
}

/// The one-shot that plays before a post-class card settles.
enum CelebrationIntro {
  /// Icon pops, a rotating ring of particles expands then collapses.
  orbit,

  /// Particles fire outward once and fade where they land.
  burst,

  /// Icon rises from below with a trailing blur and settles.
  rise,

  /// Icon flips on the Y axis; the count starts mid-flip.
  flipCount,

  /// Card arrives settled. Stats still cascade via the reveal style.
  none;

  static CelebrationIntro fromWire(String? wire) =>
      parseFormat(values, wire, CelebrationIntro.orbit);
}

/// The per-element entrance used across the celebration stack.
enum RevealStyle {
  /// Opacity in with an upward translate. `StaggeredReveal` today.
  fadeUp,

  /// Scale from 0.5 with opacity. `ScaleReveal` today.
  scalePop,

  /// Horizontal entry from the leading edge, opacity held high.
  slideIn,

  /// Revealed by a clip along its own axis. No transform, so text
  /// stays pin-sharp throughout.
  maskWipe,

  /// Present at full opacity; stagger still orders appearance.
  none;

  static RevealStyle fromWire(String? wire) =>
      parseFormat(values, wire, RevealStyle.fadeUp);
}

/// The waiting state.
enum LoaderStyle {
  /// Three dots in a travelling wave. `LoadingDots` today.
  dots,

  /// A ring scales out and fades, repeating.
  pulseRing,

  /// An indeterminate bar sweeping its track.
  barSweep,

  /// The tenant mark breathing. The only value that is white-label
  /// native, since the mark is already a customization slot.
  logoBreathe;

  static LoaderStyle fromWire(String? wire) =>
      parseFormat(values, wire, LoaderStyle.dots);
}

/// Screen-to-screen motion.
///
/// [platformDefault] is first, and that is deliberate: the app has
/// never set a page transition, so it inherits Flutter's
/// platform-dependent default. Making any authored transition the
/// fallback would change shipped behaviour for every tenant that has
/// not opted in, which the arrangement-only invariant forbids.
enum TransitionStyle {
  /// Whatever the platform theme already does. Today's behaviour.
  platformDefault,

  /// Cross-fade, no translation.
  fade,

  /// Paired slide plus fade along the navigation axis.
  sharedAxis,

  /// Incoming screen rises over the outgoing one, which recedes.
  cardStack,

  /// Instant cut.
  none;

  static TransitionStyle fromWire(String? wire) =>
      parseFormat(values, wire, TransitionStyle.platformDefault);
}

/// How an earned figure arrives.
enum CountUpStyle {
  /// Per-digit reels on a steep ease-out-expo. `CountUpText` today.
  odometer,

  /// The whole number re-renders through intermediate values.
  ticker,

  /// The figure holds while an arc sweeps to the value beneath it.
  sweepArc,

  /// Final value on arrival; still respects the reveal style.
  instant;

  static CountUpStyle fromWire(String? wire) =>
      parseFormat(values, wire, CountUpStyle.odometer);
}
