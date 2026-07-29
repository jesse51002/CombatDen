import 'package:mobile_app/core/formats/motion_formats.dart';

/// One mark's complete visual state at one instant, expressed on the
/// loader's own normalised box.
///
/// Every default is the mark AT REST, so a value that leaves a channel
/// alone contributes no motion on that axis.
class LoaderMark {
  const LoaderMark({
    this.x = 0,
    this.lift = 0,
    this.scale = 1,
    this.opacity = 1,
  });

  /// Horizontal position: -1 flush with the box's leading edge, 0
  /// centred, 1 flush with the trailing edge. The mark's own extent is
  /// taken out of the travel, so no value can push a mark outside the
  /// box it shares with every other value.
  final double x;

  /// How far ABOVE its rest line the mark sits, 0 at rest to 1 at full
  /// lift. Never negative: a mark that dips below its rest line is an
  /// overshoot wearing a translation.
  final double lift;

  /// Extent as a fraction of the mark's nominal size. Never above 1 —
  /// the app's motion law is ease-out only, so nothing may pass its
  /// settled size.
  final double scale;

  final double opacity;
}

/// Every mark a loader draws at one instant.
class LoaderFrame {
  const LoaderFrame(this.marks);

  final List<LoaderMark> marks;
}

/// The primitive a value's marks are drawn as.
///
/// Declared once per value and never animated: the shape is what the
/// loader IS, the frame is only where its marks are. That split is what
/// keeps a value from growing a second indicator halfway through a
/// cycle.
enum LoaderShape {
  /// Filled brand circles. `dots` today.
  dot,

  /// A stroked brand ring, centred.
  ring,

  /// A capsule riding a full-width track.
  bar,

  /// The tenant's mark, resolved from the `logo_primary` image slot.
  mark,
}

/// One loader value's whole contract: what it draws, how long one cycle
/// runs, how many marks it carries, and the pure function that produces
/// its frames.
///
/// The four specs are the only thing that differs between values. Adding
/// a value means adding a spec — there is no seam through which it could
/// reach the screen it is waiting on.
class LoaderSpec {
  const LoaderSpec({
    required this.value,
    required this.shape,
    required this.cycle,
    required this.markCount,
    required this.frameAt,
  });

  final LoaderStyle value;
  final LoaderShape shape;

  /// One full repeat. A loader is indefinite, so this is a TEMPO, not a
  /// lifetime — nothing here says when the loader ends, because it does
  /// not: the parent decides when to swap it out.
  ///
  /// It also has to be long enough to read AS a cycle. Below roughly
  /// eight tenths of a second a repeat registers as a flicker or a
  /// fault rather than as work in progress, and a frantic loader makes
  /// a wait feel worse than a calm one. The invariants gate holds that
  /// floor.
  final Duration cycle;

  /// How many marks [frameAt] returns, at every t. Fixed per value: the
  /// count is part of the figure, never something the motion adds or
  /// drops mid-cycle.
  final int markCount;

  /// `t` is the phase, 0..1, and it WRAPS: `frameAt(0)` and `frameAt(1)`
  /// must describe the same instant, or the loop would cut back to its
  /// start once a cycle instead of running continuously.
  final LoaderFrame Function(double t) frameAt;
}
