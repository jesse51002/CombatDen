import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mobile_app/shared/widgets/animation/capture_reveal_clock.dart';
import 'package:mobile_app/shared/widgets/animation/celebration_timings.dart';

/// A number that rolls from 0 to [target] using a steep ease-out-exp curve
/// over [duration]. Implemented as the standard **odometer / slot-counter
/// reel**: one vertical strip per digit position, each strip listing every
/// integer that digit will pass through, translated by `translateY` and
/// clipped to a one-digit-tall window. The visible digit slides in from
/// below and the previous one slides up out the top — no widget swap, no
/// fade — exactly the technique `odometer` (web) and `react-slot-counter`
/// use. Curve deceleration shapes the spin: fast scroll up front, slow
/// landing on the final digits.
class CountUpText extends StatefulWidget {
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
  final Duration duration;
  final Duration delay;
  final String prefix;
  final String suffix;
  final TextAlign? textAlign;

  @override
  State<CountUpText> createState() => _CountUpTextState();
}

class _CountUpTextState extends State<CountUpText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Size _digitSize;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _digitSize = _measureDigitCell(widget.style);
    // When the capture clock is driving, the harness sets the progress (with
    // [delay] read as this reel's absolute offset on the global timeline);
    // don't run the self-animation. Mirrors ScaleReveal/StaggeredReveal.
    if (captureRevealClock.value != null) return;
    if (widget.delay == Duration.zero) {
      _ctrl.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _ctrl.forward();
      });
    }
  }

  /// Raw 0..1 progress: from the capture clock (minus this reel's [delay], used
  /// as its absolute start offset on the global timeline) when capturing, else
  /// the controller. The easeOutExpo shaping is applied per-reel in [_DigitReel].
  double _effectiveValue() {
    final clock = captureRevealClock.value;
    if (clock == null) return _ctrl.value;
    return ((clock - widget.delay).inMicroseconds /
            widget.duration.inMicroseconds)
        .clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Measure a "cell": widest digit width × tallest digit height. Used to
  /// give every reel a tabular fixed-width slot so layout doesn't jitter
  /// when the visible digit changes.
  Size _measureDigitCell(TextStyle style) {
    double maxWidth = 0;
    double maxHeight = 0;
    for (var d = 0; d < 10; d++) {
      final tp = TextPainter(
        text: TextSpan(text: '$d', style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      if (tp.width > maxWidth) maxWidth = tp.width;
      if (tp.height > maxHeight) maxHeight = tp.height;
    }
    return Size(maxWidth, maxHeight);
  }

  int _digitCountFor(int n) {
    final abs = n.abs();
    return abs < 10 ? 1 : abs.toString().length;
  }

  @override
  Widget build(BuildContext context) {
    final positions = _digitCountFor(widget.target);
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (widget.prefix.isNotEmpty)
          Text(widget.prefix, style: widget.style),
        for (int p = positions - 1; p >= 0; p--) ...[
          _DigitReel(
            listenable: Listenable.merge([_ctrl, captureRevealClock]),
            value: _effectiveValue,
            target: widget.target,
            position: p,
            digitSize: _digitSize,
            style: widget.style,
          ),
          if (p > 0 && p % 3 == 0) Text(',', style: widget.style),
        ],
        if (widget.suffix.isNotEmpty)
          Text(widget.suffix, style: widget.style),
      ],
    );
  }
}

/// One vertical strip listing every value this position will pass through
/// (0..target ÷ 10^position). At any frame it's translated up by
/// `reelValue × digitHeight`, so the visible window centers on the digit
/// the eased counter currently lands on. Sub-integer reel values place
/// the window between two cells — this is what produces the slot-machine
/// "blur scroll" early and the clean landing late.
class _DigitReel extends StatefulWidget {
  const _DigitReel({
    required this.listenable,
    required this.value,
    required this.target,
    required this.position,
    required this.digitSize,
    required this.style,
  });

  /// Rebuild trigger — the controller merged with the capture clock.
  final Listenable listenable;

  /// Raw 0..1 progress for the current frame (controller- or clock-driven).
  final double Function() value;
  final int target;
  final int position;
  final Size digitSize;
  final TextStyle style;

  @override
  State<_DigitReel> createState() => _DigitReelState();
}

class _DigitReelState extends State<_DigitReel> {
  late final int _divisor = math.pow(10, widget.position).toInt();
  late final int _maxIndex = widget.target ~/ _divisor;
  // Strip widget is built once per reel instance and reused every frame
  // via AnimatedBuilder's `child` parameter — only the wrapping Transform
  // rebuilds each tick.
  late final Widget _strip = _buildStrip();

  Widget _buildStrip() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i <= _maxIndex; i++)
          SizedBox(
            width: widget.digitSize.width,
            height: widget.digitSize.height,
            child: Center(
              child: Text('${i % 10}', style: widget.style),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.digitSize.width,
      height: widget.digitSize.height,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: widget.listenable,
          child: _strip,
          builder: (context, child) {
            final eased = Curves.easeOutExpo.transform(widget.value());
            final reelValue = (eased * widget.target / _divisor)
                .clamp(0.0, _maxIndex.toDouble());
            return OverflowBox(
              maxHeight: double.infinity,
              alignment: Alignment.topCenter,
              child: Transform.translate(
                offset: Offset(0, -reelValue * widget.digitSize.height),
                child: child,
              ),
            );
          },
        ),
      ),
    );
  }
}
