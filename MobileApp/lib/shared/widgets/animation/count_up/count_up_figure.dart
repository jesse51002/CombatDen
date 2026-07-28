import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';
import 'package:mobile_app/shared/widgets/animation/count_up/count_up_arc_painter.dart';
import 'package:mobile_app/shared/widgets/animation/count_up/count_up_digit.dart';
import 'package:mobile_app/shared/widgets/animation/count_up/count_up_frame.dart';

/// The one widget that paints a [CountUpFrame].
///
/// Every value renders through here, which is what makes the invariant
/// mechanical rather than promised: the same prefix, the same digit
/// positions in the same fixed-width cells, the same thousands
/// separators, and the same suffix are assembled for every value. A
/// value only chooses what goes INSIDE a digit cell (a reel or a glyph)
/// and whether an arc is painted behind the lot — neither of which can
/// change the string, the style, or the size of the box.
class CountUpFigure extends StatelessWidget {
  const CountUpFigure({
    super.key,
    required this.spec,
    required this.listenable,
    required this.frame,
    required this.target,
    required this.digitSize,
    required this.style,
    required this.prefix,
    required this.suffix,
  });

  final CountUpSpec spec;

  /// Rebuild trigger — the driver's controller merged with the capture
  /// clock.
  final Listenable listenable;

  /// The current frame, recomputed per tick by the driver.
  final CountUpFrame Function() frame;

  final int target;

  /// The tabular cell every digit position occupies: widest digit width
  /// × tallest digit height, measured once by the driver so the figure
  /// does not jitter when the visible digit changes.
  final Size digitSize;

  final TextStyle style;
  final String prefix;
  final String suffix;

  /// Marks one digit position, so the invariants gate can read what is
  /// actually on screen for whichever slot kind a value chose.
  static Key slotKey(int position) => ValueKey('count-up-slot-$position');

  /// How many digit positions [target] occupies.
  static int digitCountFor(int target) {
    final abs = target.abs();
    return abs < 10 ? 1 : abs.toString().length;
  }

  /// The figure at rest, as one string — the same derivation the row
  /// below is built from, so the two cannot drift.
  ///
  /// This is also what the count-up reads out: the digits are a
  /// presentation device (a reel is a column of ten glyphs, not a
  /// number), so the whole figure is announced once here instead of
  /// leaving assistive tech to walk a strip.
  static String settledLabel({
    required int target,
    required String prefix,
    required String suffix,
  }) {
    final buffer = StringBuffer(prefix);
    final positions = digitCountFor(target);
    for (var p = positions - 1; p >= 0; p--) {
      buffer.write((target ~/ math.pow(10, p).toInt()) % 10);
      if (p > 0 && p % 3 == 0) buffer.write(',');
    }
    return (buffer..write(suffix)).toString();
  }

  Widget _slot(int position) {
    return SizedBox(
      key: slotKey(position),
      width: digitSize.width,
      height: digitSize.height,
      child: spec.reeled
          ? CountUpDigitReel(
              listenable: listenable,
              frame: frame,
              target: target,
              position: position,
              digitSize: digitSize,
              style: style,
            )
          : CountUpDigitCell(
              listenable: listenable,
              frame: frame,
              target: target,
              position: position,
              style: style,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final positions = digitCountFor(target);
    final figure = Semantics(
      container: true,
      excludeSemantics: true,
      label: settledLabel(target: target, prefix: prefix, suffix: suffix),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (prefix.isNotEmpty) Text(prefix, style: style),
          for (var p = positions - 1; p >= 0; p--) ...[
            _slot(p),
            if (p > 0 && p % 3 == 0) Text(',', style: style),
          ],
          if (suffix.isNotEmpty) Text(suffix, style: style),
        ],
      ),
    );

    if (!spec.hasArc) return figure;

    // `CustomPaint` WITH a child takes the child's size, so the arc is
    // painted behind the figure without ever contributing to layout —
    // mid-sweep or settled.
    return AnimatedBuilder(
      animation: listenable,
      child: figure,
      builder: (context, child) {
        final current = frame();
        return CustomPaint(
          painter: CountUpArcPainter(
            sweep: current.arcSweep,
            opacity: current.arcOpacity,
            color: style.color ?? DesignConstants.text,
            strokeWidth: DesignConstants.buttonBorder,
          ),
          child: child,
        );
      },
    );
  }
}
