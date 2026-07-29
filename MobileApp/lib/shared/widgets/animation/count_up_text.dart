import 'package:flutter/material.dart';
import 'package:mobile_app/core/formats/format_builder.dart';
import 'package:mobile_app/core/formats/motion_formats.dart';
import 'package:mobile_app/core/formats/theme_motion.dart';
import 'package:mobile_app/shared/widgets/animation/capture_reveal_clock.dart';
import 'package:mobile_app/shared/widgets/animation/celebration_timings.dart';
import 'package:mobile_app/shared/widgets/animation/count_up/count_up_figure.dart';
import 'package:mobile_app/shared/widgets/animation/count_up/count_up_frame.dart';
import 'package:mobile_app/shared/widgets/animation/count_up/count_up_instant.dart';
import 'package:mobile_app/shared/widgets/animation/count_up/count_up_odometer.dart';
import 'package:mobile_app/shared/widgets/animation/count_up/count_up_sweep_arc.dart';
import 'package:mobile_app/shared/widgets/animation/count_up/count_up_ticker.dart';

/// An earned figure arriving at [target], on the tenant's
/// `count_up_style`.
///
/// The value supplies the timing and the entrance and nothing else: the
/// same prefix, the same digits, the same separators, the same suffix
/// and the same box arrive whichever one is active — see
/// `animation/count_up/` for the frame model, and
/// `test/count_up_style_invariants_test.dart` for the gate that proves
/// it.
///
/// [delay] keeps its two meanings: in the app it is how long the figure
/// waits before it starts, and under capture it is this figure's
/// absolute offset on the global timeline. That is what lets
/// `CelebrationIntro.flipCount` hand the card over mid-flip with the
/// count-up already placed on the clock.
class CountUpText extends StatelessWidget {
  const CountUpText({
    super.key,
    required this.target,
    required this.style,
    this.duration = CelebrationTimings.countUpDuration,
    this.delay = Duration.zero,
    this.prefix = '',
    this.suffix = '',
    this.textAlign,
  });

  final int target;
  final TextStyle style;

  /// The reference length each value scales its own run from.
  final Duration duration;

  final Duration delay;
  final String prefix;
  final String suffix;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    // Local rebuild, so the dev picker swaps the value in place. Keyed on
    // the value so a swap restarts the count rather than leaving a
    // half-played controller on the new timing.
    return FormatBuilder(
      builder: (context) {
        final spec = countUpSpec(ThemeMotion.countUp());
        return _CountUpRunner(
          key: ValueKey(spec.value),
          spec: spec,
          target: target,
          style: style,
          reference: duration,
          delay: delay,
          prefix: prefix,
          suffix: suffix,
        );
      },
    );
  }
}

/// The value -> implementation switch. One entry per value, no defaults:
/// adding a value is a compile error until it has a spec.
CountUpSpec countUpSpec(CountUpStyle value) => switch (value) {
  CountUpStyle.odometer => kOdometerCountUp,
  CountUpStyle.ticker => kTickerCountUp,
  CountUpStyle.sweepArc => kSweepArcCountUp,
  CountUpStyle.instant => kInstantCountUp,
};

class _CountUpRunner extends StatefulWidget {
  const _CountUpRunner({
    super.key,
    required this.spec,
    required this.target,
    required this.style,
    required this.reference,
    required this.delay,
    required this.prefix,
    required this.suffix,
  });

  final CountUpSpec spec;
  final int target;
  final TextStyle style;
  final Duration reference;
  final Duration delay;
  final String prefix;
  final String suffix;

  @override
  State<_CountUpRunner> createState() => _CountUpRunnerState();
}

class _CountUpRunnerState extends State<_CountUpRunner>
    with SingleTickerProviderStateMixin {
  /// Null for a value that does not animate.
  AnimationController? _ctrl;
  late final Duration _total;
  late final Size _digitSize;
  late final Listenable _listenable;

  @override
  void initState() {
    super.initState();
    _digitSize = _measureDigitCell(widget.style);
    _total = widget.spec.totalFor(widget.reference);

    if (!widget.spec.isInstant) {
      _ctrl = AnimationController(vsync: this, duration: _total);
    }
    _listenable = Listenable.merge([?_ctrl, captureRevealClock]);
    if (_ctrl == null) return;

    // When the capture clock is driving, the harness sets the progress
    // (with [delay] read as this figure's absolute offset on the global
    // timeline); don't run the self-animation. Mirrors
    // ScaleReveal/StaggeredReveal.
    if (captureRevealClock.value != null) return;
    if (widget.delay == Duration.zero) {
      _ctrl!.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _ctrl!.forward();
      });
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  /// Raw 0..1 progress: from the capture clock (minus this figure's
  /// [delay], used as its absolute start offset on the global timeline)
  /// when capturing, else the controller. The value's own curve is
  /// applied by its spec, not here.
  double _rawProgress() {
    if (_ctrl == null) return 1;
    final clock = captureRevealClock.value;
    if (clock == null) return _ctrl!.value;
    return ((clock - widget.delay).inMicroseconds / _total.inMicroseconds)
        .clamp(0.0, 1.0);
  }

  CountUpFrame _frame() => widget.spec.frameAt(_rawProgress());

  /// Measure a "cell": widest digit width × tallest digit height. Used to
  /// give every position a tabular fixed-width slot so layout doesn't
  /// jitter when the visible digit changes — and so every value occupies
  /// exactly the same box.
  Size _measureDigitCell(TextStyle style) {
    var maxWidth = 0.0;
    var maxHeight = 0.0;
    for (var d = 0; d < 10; d++) {
      final painter = TextPainter(
        text: TextSpan(text: '$d', style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      if (painter.width > maxWidth) maxWidth = painter.width;
      if (painter.height > maxHeight) maxHeight = painter.height;
    }
    return Size(maxWidth, maxHeight);
  }

  @override
  Widget build(BuildContext context) {
    return CountUpFigure(
      spec: widget.spec,
      listenable: _listenable,
      frame: _frame,
      target: widget.target,
      digitSize: _digitSize,
      style: widget.style,
      prefix: widget.prefix,
      suffix: widget.suffix,
    );
  }
}
