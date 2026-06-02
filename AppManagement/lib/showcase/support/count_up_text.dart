import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:theme_flutter/theme/animation/celebration_timings.dart';

/// Clone of MobileApp's `CountUpText`: an odometer/slot-counter that rolls
/// 0 → [target] with a steep ease-out-expo curve. One vertical reel per
/// digit, translated and clipped to a one-digit window.
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
    if (widget.delay == Duration.zero) {
      _ctrl.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _ctrl.forward();
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

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
            controller: _ctrl,
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

class _DigitReel extends StatefulWidget {
  const _DigitReel({
    required this.controller,
    required this.target,
    required this.position,
    required this.digitSize,
    required this.style,
  });

  final AnimationController controller;
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
  late final Widget _strip = _buildStrip();

  Widget _buildStrip() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i <= _maxIndex; i++)
          SizedBox(
            width: widget.digitSize.width,
            height: widget.digitSize.height,
            child: Center(child: Text('${i % 10}', style: widget.style)),
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
          animation: widget.controller,
          child: _strip,
          builder: (context, child) {
            final eased =
                Curves.easeOutExpo.transform(widget.controller.value);
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
