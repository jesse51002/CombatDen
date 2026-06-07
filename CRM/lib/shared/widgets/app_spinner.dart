import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The app's shared loading indicator — **"Sweep"**: a faint hairline ring
/// with a single sapphire → accent-dark gradient arc that orbits it,
/// lengthening as it accelerates and shrinking as it eases. The brand's
/// donut / progress-arc motif set in motion — one calm sapphire voice, no
/// bounce. The trailing edge fades to nothing (a comet), the leading edge
/// deepens.
///
/// Drop-in everywhere a small in-place loader is needed; defaults to
/// [DesignConstants.iconSizeLarge] (24) so existing call sites are
/// unchanged. Honors reduced-motion: renders a static resting arc and runs
/// no animation when the OS asks for less motion.
class AppSpinner extends StatefulWidget {
  const AppSpinner({super.key, this.size, this.strokeWidth});

  /// Outer diameter. Defaults to [DesignConstants.iconSizeLarge].
  final double? size;

  /// Stroke width of the arc + track. Defaults to ~1/9 of the diameter.
  final double? strokeWidth;

  @override
  State<AppSpinner> createState() => _AppSpinnerState();
}

class _AppSpinnerState extends State<AppSpinner>
    with SingleTickerProviderStateMixin {
  // One calm revolution-plus per cycle.
  static const _period = Duration(milliseconds: 1400);

  // The resting phase shown under reduced motion — the peak-breath
  // frame, a full, deliberate gradient arc.
  static const _staticPhase = 0.5;

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: _period,
  );

  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce == _reduceMotion && (reduce || _ctrl.isAnimating)) {
      return;
    }
    _reduceMotion = reduce;
    if (reduce) {
      _ctrl.stop();
    } else {
      _ctrl.repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size ?? DesignConstants.iconSizeLarge;
    final stroke = widget.strokeWidth ?? size / 9;
    return SizedBox(
      width: size,
      height: size,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            return CustomPaint(
              painter: _SweepPainter(
                t: _reduceMotion ? _staticPhase : _ctrl.value,
                stroke: stroke,
                arc: DesignConstants.primaryColor,
                arcDeep: DesignConstants.accentDark,
                track: DesignConstants.divider,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Paints the Sweep: a faint full-circle hairline track, then one
/// gradient arc whose head leads (first three-quarters of the cycle) and
/// tail follows (offset), so the arc breathes between a short nub and a
/// long sweep while it orbits.
class _SweepPainter extends CustomPainter {
  _SweepPainter({
    required this.t,
    required this.stroke,
    required this.arc,
    required this.arcDeep,
    required this.track,
  });

  final double t;
  final double stroke;
  final Color arc;
  final Color arcDeep;
  final Color track;

  /// The arc never fully vanishes — a small nub always remains.
  static const _minSweep = 0.06; // fraction of a full turn
  static const _twoPi = 2 * math.pi;

  @override
  void paint(Canvas canvas, Size size) {
    final arcRect = (Offset.zero & size).deflate(stroke / 2);

    // Faint hairline track (full circle).
    canvas.drawArc(
      arcRect,
      0,
      _twoPi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );

    // Head leads over [0, .75]; tail follows over [.25, 1] — the gap
    // between them grows then shrinks (the breath). A base spin keeps it
    // orbiting so it never dwells.
    final head = Curves.easeInOutCubic.transform(_seg(t, 0.0, 0.75));
    final tail = Curves.easeInOutCubic.transform(_seg(t, 0.25, 1.0));
    final sweepFrac = math.max(_minSweep, head - tail);
    final startAngle = (t + tail) * _twoPi - math.pi / 2;
    final sweepAngle = sweepFrac * _twoPi;

    // Gradient along the arc: a transparent (comet) tail → sapphire →
    // deeper accent head.
    final shader = SweepGradient(
      startAngle: startAngle,
      endAngle: startAngle + sweepAngle,
      colors: [arc.withValues(alpha: 0.0), arc, arcDeep],
      stops: const [0.0, 0.4, 1.0],
      tileMode: TileMode.clamp,
    ).createShader(arcRect);

    canvas.drawArc(
      arcRect,
      startAngle,
      sweepAngle,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = shader,
    );
  }

  /// Normalize [v] into [0,1] across the window [a,b], clamped.
  double _seg(double v, double a, double b) =>
      ((v - a) / (b - a)).clamp(0.0, 1.0);

  @override
  bool shouldRepaint(_SweepPainter old) =>
      old.t != t ||
      old.stroke != stroke ||
      old.arc != arc ||
      old.arcDeep != arcDeep ||
      old.track != track;
}
