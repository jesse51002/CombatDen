part of 'app_spinner.dart';

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
