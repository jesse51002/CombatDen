import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mobile_app/shared/widgets/animation/count_up/count_up_frame.dart';

/// One digit position of the figure, rendered as a reel.
///
/// A vertical strip listing every value this position will pass through
/// (0..target ÷ 10^position). At any frame it is translated up by
/// `reelValue × digitHeight`, so the visible window centres on the digit
/// the counter currently lands on. Sub-integer reel values place the
/// window between two cells — this is what produces the slot-machine
/// blur scroll early and the clean landing late.
///
/// Only `odometer` declares [CountUpSpec.reeled], so only `odometer`
/// pays for the strip.
class CountUpDigitReel extends StatefulWidget {
  const CountUpDigitReel({
    super.key,
    required this.listenable,
    required this.frame,
    required this.target,
    required this.position,
    required this.digitSize,
    required this.style,
  });

  /// Rebuild trigger — the controller merged with the capture clock.
  final Listenable listenable;

  /// The current frame, recomputed per tick by the driver.
  final CountUpFrame Function() frame;

  final int target;
  final int position;
  final Size digitSize;
  final TextStyle style;

  @override
  State<CountUpDigitReel> createState() => _CountUpDigitReelState();
}

class _CountUpDigitReelState extends State<CountUpDigitReel> {
  late final int _divisor = math.pow(10, widget.position).toInt();
  late final int _maxIndex = widget.target ~/ _divisor;
  // Built once per reel instance and reused every frame via
  // AnimatedBuilder's `child` parameter — only the wrapping Transform
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
            child: Center(child: Text('${i % 10}', style: widget.style)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedBuilder(
        animation: widget.listenable,
        child: _strip,
        builder: (context, child) {
          final reelValue = (widget.frame().progress * widget.target / _divisor)
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
    );
  }
}

/// One digit position of the figure, rendered as a single glyph.
///
/// No per-digit motion: the position simply shows whichever digit the
/// whole number is currently on, so the figure re-renders through its
/// intermediate values. A handful of glyphs instead of a strip per
/// position, which is the entire cost difference between this and
/// [CountUpDigitReel].
class CountUpDigitCell extends StatelessWidget {
  const CountUpDigitCell({
    super.key,
    required this.listenable,
    required this.frame,
    required this.target,
    required this.position,
    required this.style,
  });

  final Listenable listenable;
  final CountUpFrame Function() frame;
  final int target;
  final int position;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final divisor = math.pow(10, position).toInt();
    return AnimatedBuilder(
      animation: listenable,
      builder: (context, _) {
        final digit = (frame().displayedValue(target) ~/ divisor) % 10;
        return Center(child: Text('$digit', style: style));
      },
    );
  }
}
