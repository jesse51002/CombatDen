import 'package:flutter/material.dart';
import 'package:mobile_app/core/formats/format_builder.dart';
import 'package:mobile_app/core/formats/motion_formats.dart';
import 'package:mobile_app/core/formats/theme_motion.dart';
import 'package:mobile_app/shared/widgets/animation/capture_reveal_clock.dart';
import 'package:mobile_app/shared/widgets/post_class/intro/celebration_intro_figure.dart';
import 'package:mobile_app/shared/widgets/post_class/intro/celebration_intro_frame.dart';
import 'package:mobile_app/shared/widgets/post_class/intro/intro_burst.dart';
import 'package:mobile_app/shared/widgets/post_class/intro/intro_flip_count.dart';
import 'package:mobile_app/shared/widgets/post_class/intro/intro_orbit.dart';
import 'package:mobile_app/shared/widgets/post_class/intro/intro_rise.dart';
import 'package:mobile_app/shared/widgets/post_class/post_class_controller.dart';

/// Builds a card's settled content. [captureOffset] is set only under
/// capture: it is the absolute point on the global capture timeline at
/// which this content starts, so the card's own reveals and count-ups
/// can be placed on that timeline instead of relative to mount.
typedef CelebrationSettledBuilder =
    Widget Function(BuildContext context, Duration? captureOffset);

/// The one-shot that plays before a post-class card settles, selected by
/// the tenant's `celebration_intro` slot.
///
/// The card supplies its hero mark, its particle mark, and its settled
/// content; the value supplies the timing and the entrance and nothing
/// else. That is the whole invariant: whichever value is active, the
/// same settled content arrives, and the
/// [PostClassController] contract around it — CTA hidden while playing,
/// a tap on the stage jumping to the final state, exactly one
/// `markDone` — is implemented once here rather than per value.
class CelebrationIntroStage extends StatelessWidget {
  const CelebrationIntroStage({
    super.key,
    required this.hero,
    required this.particle,
    required this.settled,
    this.controller,
  });

  /// The figure the intro moves. Never part of the settled content.
  final ImageProvider hero;

  /// The mark the particle field is made of. Only the values that
  /// declare a field render it.
  final ImageProvider particle;

  final CelebrationSettledBuilder settled;
  final PostClassController? controller;

  @override
  Widget build(BuildContext context) {
    // Local rebuild, so the dev picker swaps the intro in place. Keyed on
    // the value so a swap restarts the intro rather than leaving a
    // half-played controller on the new timing.
    return FormatBuilder(
      builder: (context) {
        final spec = introSpec(ThemeMotion.celebrationIntro());
        return _IntroRunner(
          key: ValueKey(spec.value),
          spec: spec,
          hero: hero,
          particle: particle,
          settled: settled,
          controller: controller,
        );
      },
    );
  }
}

/// The value -> implementation switch. One entry per value, no defaults:
/// adding a value is a compile error until it has a spec.
CelebrationIntroSpec introSpec(CelebrationIntro value) => switch (value) {
  CelebrationIntro.orbit => kOrbitIntro,
  CelebrationIntro.burst => kBurstIntro,
  CelebrationIntro.rise => kRiseIntro,
  CelebrationIntro.flipCount => kFlipCountIntro,
};

class _IntroRunner extends StatefulWidget {
  const _IntroRunner({
    super.key,
    required this.spec,
    required this.hero,
    required this.particle,
    required this.settled,
    required this.controller,
  });

  final CelebrationIntroSpec spec;
  final ImageProvider hero;
  final ImageProvider particle;
  final CelebrationSettledBuilder settled;
  final PostClassController? controller;

  @override
  State<_IntroRunner> createState() => _IntroRunnerState();
}

class _IntroRunnerState extends State<_IntroRunner>
    with SingleTickerProviderStateMixin {
  static const Key _kSettledKey = Key('celebration-intro-settled');
  static const Key _kFigureKey = Key('celebration-intro-figure');

  late final AnimationController _ctrl;
  // Held as a field so the controller can release exactly this handler
  // and not a replacement's — see `clearSkipHandler`.
  late final VoidCallback _skip = _skipToFinal;
  bool _skipped = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.spec.total);
    widget.controller?.registerSkipHandler(_skip);

    // Under capture the harness drives the intro from the global clock;
    // don't self-run, and so never finish — the settled state arrives on
    // the clock threshold instead, and the harness holds the CTA hidden
    // for the whole clip. Mirrors ScaleReveal/StaggeredReveal.
    if (captureRevealClock.value != null) return;

    _ctrl.forward().whenComplete(_finish);
  }

  @override
  void dispose() {
    widget.controller?.clearSkipHandler(_skip);
    _ctrl.dispose();
    super.dispose();
  }

  /// Jump straight to the settled state. The controller is left running
  /// rather than cancelled; [_finish] is idempotent, so its completion
  /// is a no-op once we are already done.
  void _skipToFinal() {
    if (!mounted || _skipped) return;
    setState(() => _skipped = true);
    _finish();
  }

  void _finish() {
    if (!mounted || _done) return;
    _done = true;
    widget.controller?.markDone();
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    return AnimatedBuilder(
      animation: Listenable.merge([_ctrl, captureRevealClock]),
      builder: (context, _) {
        final clock = captureRevealClock.value;
        final totalUs = spec.total.inMicroseconds;

        final double t;
        if (_skipped) {
          t = 1;
        } else if (clock != null) {
          t = (clock.inMicroseconds / totalUs).clamp(0.0, 1.0);
        } else {
          t = _ctrl.value;
        }

        // The intro owns the stage until it is done. One or the other,
        // never both: the figure fills the stage while it plays, then
        // the settled content sizes to itself and the stage's own
        // alignment places it, exactly as the shipped card always did.
        if (!_skipped && t < 1) {
          return SizedBox.expand(
            child: KeyedSubtree(
              key: _kFigureKey,
              child: IgnorePointer(
                child: CelebrationIntroFigure(
                  spec: spec,
                  frame: spec.frameAt(t),
                  hero: widget.hero,
                  particle: widget.particle,
                ),
              ),
            ),
          );
        }
        return KeyedSubtree(
          key: _kSettledKey,
          child: widget.settled(context, clock != null ? spec.total : null),
        );
      },
    );
  }
}
