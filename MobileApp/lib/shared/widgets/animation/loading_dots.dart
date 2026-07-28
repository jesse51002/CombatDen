import 'package:flutter/widgets.dart';
import 'package:mobile_app/core/formats/format_builder.dart';
import 'package:mobile_app/core/formats/motion_formats.dart';
import 'package:mobile_app/core/formats/theme_motion.dart';
import 'package:mobile_app/shared/widgets/animation/loader/loader_bar_sweep.dart';
import 'package:mobile_app/shared/widgets/animation/loader/loader_box.dart';
import 'package:mobile_app/shared/widgets/animation/loader/loader_dots.dart';
import 'package:mobile_app/shared/widgets/animation/loader/loader_figure.dart';
import 'package:mobile_app/shared/widgets/animation/loader/loader_frame.dart';
import 'package:mobile_app/shared/widgets/animation/loader/loader_logo_breathe.dart';
import 'package:mobile_app/shared/widgets/animation/loader/loader_pulse_ring.dart';

/// The app's ONE waiting state, drawn in the tenant's `loader_style`.
///
/// Every surface that waits on something shows this widget, so a tenant
/// picks a loader once and the whole app waits the same way. The value
/// supplies the tempo and the figure and nothing else: whichever one is
/// active, the loader fills the same box, says nothing, and never
/// settles — a loader that stopped would be a bug, not a format.
///
/// [dotSize], [spacing] and [bounceHeight] are the shipped dots'
/// geometry and, through it, the box EVERY value fills:
/// `3·dotSize + 2·spacing` wide by `dotSize + bounceHeight` tall.
class LoadingDots extends StatelessWidget {
  const LoadingDots({
    super.key,
    this.dotSize = 24,
    this.spacing = 16,
    this.bounceHeight = 28,
    this.value,
  });

  final double dotSize;
  final double spacing;
  final double bounceHeight;

  /// When null (the default, used everywhere in the app) the loader runs
  /// itself on a repeating controller. When set (0..1) the cycle is
  /// rendered at exactly that phase and NOTHING self-animates — the
  /// capture harness (`tools/capture/`) drives this per frame so the
  /// exported clip plays at true speed.
  final double? value;

  @override
  Widget build(BuildContext context) {
    // The box is the shipped dots' own footprint, derived from its spec
    // rather than restated, so the two can never drift apart.
    final dots = kDotsLoader.markCount;
    final box = LoaderBox(
      size: Size(
        dots * dotSize + (dots - 1) * spacing,
        dotSize + bounceHeight,
      ),
      markExtent: dotSize,
      liftSpan: bounceHeight,
    );
    // Local rebuild, so the dev picker swaps the loader in place. Keyed
    // on the value so a swap restarts the cycle on the new tempo rather
    // than leaving a half-run controller on the old one.
    return FormatBuilder(
      builder: (context) {
        final spec = loaderSpec(ThemeMotion.loader());
        return _LoaderRunner(
          key: ValueKey(spec.value),
          spec: spec,
          box: box,
          value: value,
        );
      },
    );
  }
}

/// The value -> implementation switch. One entry per value, no default:
/// adding a value is a compile error until it has a spec.
LoaderSpec loaderSpec(LoaderStyle value) => switch (value) {
  LoaderStyle.dots => kDotsLoader,
  LoaderStyle.pulseRing => kPulseRingLoader,
  LoaderStyle.barSweep => kBarSweepLoader,
  LoaderStyle.logoBreathe => kLogoBreatheLoader,
};

class _LoaderRunner extends StatefulWidget {
  const _LoaderRunner({
    super.key,
    required this.spec,
    required this.box,
    required this.value,
  });

  final LoaderSpec spec;
  final LoaderBox box;
  final double? value;

  @override
  State<_LoaderRunner> createState() => _LoaderRunnerState();
}

class _LoaderRunnerState extends State<_LoaderRunner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: widget.spec.cycle,
  );

  @override
  void initState() {
    super.initState();
    // Indefinite by definition: it repeats until the parent takes it
    // away. When a phase is pinned the caller owns it, so nothing runs.
    if (widget.value == null) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant _LoaderRunner old) {
    super.didUpdateWidget(old);
    // A caller that starts or stops pinning the phase mid-life gets what
    // it asked for, rather than a controller left running underneath a
    // pinned frame.
    if ((widget.value == null) == (old.value == null)) return;
    if (widget.value == null) {
      _ctrl.repeat();
    } else {
      _ctrl.stop();
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
      animation: _ctrl,
      builder: (context, _) {
        final t = widget.value ?? _ctrl.value;
        return LoaderFigure(
          spec: widget.spec,
          frame: widget.spec.frameAt(t),
          box: widget.box,
        );
      },
    );
  }
}
