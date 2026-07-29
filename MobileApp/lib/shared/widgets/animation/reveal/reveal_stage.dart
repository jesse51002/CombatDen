import 'package:flutter/widgets.dart';
import 'package:mobile_app/core/formats/format_builder.dart';
import 'package:mobile_app/core/formats/motion_formats.dart';
import 'package:mobile_app/core/formats/theme_motion.dart';
import 'package:mobile_app/shared/widgets/animation/capture_reveal_clock.dart';
import 'package:mobile_app/shared/widgets/animation/celebration_timings.dart';
import 'package:mobile_app/shared/widgets/animation/reveal/reveal_fade_up.dart';
import 'package:mobile_app/shared/widgets/animation/reveal/reveal_figure.dart';
import 'package:mobile_app/shared/widgets/animation/reveal/reveal_frame.dart';
import 'package:mobile_app/shared/widgets/animation/reveal/reveal_mask_wipe.dart';
import 'package:mobile_app/shared/widgets/animation/reveal/reveal_scale_pop.dart';
import 'package:mobile_app/shared/widgets/animation/reveal/reveal_slide_in.dart';

/// The value -> implementation switch. One entry per value, no default:
/// adding a value is a compile error until it has a spec.
RevealSpec revealSpec(RevealStyle value) => switch (value) {
  RevealStyle.fadeUp => kFadeUpReveal,
  RevealStyle.scalePop => kScalePopReveal,
  RevealStyle.slideIn => kSlideInReveal,
  RevealStyle.maskWipe => kMaskWipeReveal,
};

/// One element's entrance, in whichever style the tenant's
/// `reveal_style` slot resolves to.
///
/// `StaggeredReveal` and `ScaleReveal` are the two public faces of this;
/// they differ only in the [RevealGeometry] they bring. Everything about
/// WHEN an element enters — the call site's `delay`, and therefore the
/// stagger order of a cascade — belongs to the call site and is
/// untouched by the value. All the value owns is HOW.
class Reveal extends StatelessWidget {
  const Reveal({
    super.key,
    required this.child,
    required this.geometry,
    this.delay = Duration.zero,
    this.duration = CelebrationTimings.revealDuration,
  });

  final Widget child;
  final RevealGeometry geometry;
  final Duration delay;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    // Local rebuild, so the dev picker swaps the entrance in place.
    // Keyed on the value so a swap restarts the reveal rather than
    // leaving a half-played controller on the new timing.
    return FormatBuilder(
      builder: (context) {
        final spec = revealSpec(ThemeMotion.reveal());
        return _RevealRunner(
          key: ValueKey(spec.value),
          spec: spec,
          geometry: geometry,
          delay: delay,
          duration: duration,
          child: child,
        );
      },
    );
  }
}

class _RevealRunner extends StatefulWidget {
  const _RevealRunner({
    super.key,
    required this.spec,
    required this.geometry,
    required this.delay,
    required this.duration,
    required this.child,
  });

  final RevealSpec spec;
  final RevealGeometry geometry;
  final Duration delay;
  final Duration duration;
  final Widget child;

  @override
  State<_RevealRunner> createState() => _RevealRunnerState();
}

class _RevealRunnerState extends State<_RevealRunner>
    with SingleTickerProviderStateMixin {
  /// The call site's own delay plus the value's lead-in. The lead-in is
  /// the same for every element, so a cascade keeps exactly the order
  /// and the gaps its call sites authored.
  late final Duration _beginAt = widget.delay + widget.spec.leadIn;

  late final Duration _run = widget.spec.runFor(widget.duration);

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: _run,
  );

  /// Fixes the wrapper chain for the whole entrance — see
  /// [RevealFigure.start].
  late final RevealFrame _initialFrame =
      widget.spec.frameAt(0, widget.geometry);

  @override
  void initState() {
    super.initState();
    // When the capture clock is driving, the harness sets the progress;
    // don't run the self-animation.
    if (captureRevealClock.value != null) return;
    if (_beginAt == Duration.zero) {
      _ctrl.forward();
    } else {
      Future.delayed(_beginAt, () {
        if (mounted) _ctrl.forward();
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_ctrl, captureRevealClock]),
      builder: (context, child) {
        return RevealFigure(
          frame: widget.spec.frameAt(_progress(), widget.geometry),
          start: _initialFrame,
          child: child!,
        );
      },
      child: widget.child,
    );
  }

  /// Raw 0..1 progress. The value's own frame function applies the
  /// curve, so the self-run path and the capture path are the same
  /// arithmetic and cannot drift apart.
  double _progress() {
    final clock = captureRevealClock.value;
    if (clock == null) return _ctrl.value;
    return ((clock - _beginAt).inMicroseconds / _run.inMicroseconds)
        .clamp(0.0, 1.0);
  }
}
