import 'package:flutter/material.dart';
import 'package:customization_engine/showcase/showcase_tokens.dart';
import 'package:customization_engine/theme/animation/celebration_timings.dart';

/// Clone of MobileApp's `SparkleBurst`: a decorative one-shot sparkle scatter
/// that animates in around a hero image. Rewired to [ShowcaseTokens] for the
/// showcase island.
class SparkleBurst extends StatefulWidget {
  const SparkleBurst({
    super.key,
    this.size = 240,
    this.delay = Duration.zero,
  });

  final double size;
  final Duration delay;

  // (size, dx, dy, opacity) — radial scatter around a center point.
  static const _scatter = <(double, double, double, double)>[
    (10, -110, -90, 0.85),
    (8, 100, -100, 0.70),
    (12, 130, 30, 0.80),
    (6, -130, 20, 0.55),
    (8, -90, 110, 0.65),
    (10, 80, 110, 0.75),
    (5, 0, -130, 0.55),
    (5, 0, 130, 0.50),
    (4, -150, -30, 0.45),
    (4, 150, -40, 0.50),
    (3, 60, -70, 0.40),
    (3, -70, 60, 0.35),
  ];

  @override
  State<SparkleBurst> createState() => _SparkleBurstState();
}

class _SparkleBurstState extends State<SparkleBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: CelebrationTimings.sparkleWindow,
  );

  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    final color = ShowcaseTokens.primaryColor;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < SparkleBurst._scatter.length; i++)
                _particle(SparkleBurst._scatter[i], i, color),
            ],
          );
        },
      ),
    );
  }

  Widget _particle(
    (double, double, double, double) s,
    int index,
    Color color,
  ) {
    final n = SparkleBurst._scatter.length;
    final stagger = (index / n) * 0.65;
    final localT = ((_ctrl.value - stagger) / 0.35).clamp(0.0, 1.0);
    final eased = Curves.easeOutQuart.transform(localT);
    return Transform.translate(
      offset: Offset(s.$2, s.$3),
      child: Opacity(
        opacity: eased * s.$4,
        child: Transform.scale(
          scale: 0.6 + 0.4 * eased,
          child: SizedBox(
            width: s.$1,
            height: s.$1,
            child: CustomPaint(
              painter: _SparkleStarPainter(color: color),
            ),
          ),
        ),
      ),
    );
  }
}

class _SparkleStarPainter extends CustomPainter {
  _SparkleStarPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(12 * s, 0)
      ..lineTo(14 * s, 10 * s)
      ..lineTo(24 * s, 12 * s)
      ..lineTo(14 * s, 14 * s)
      ..lineTo(12 * s, 24 * s)
      ..lineTo(10 * s, 14 * s)
      ..lineTo(0, 12 * s)
      ..lineTo(10 * s, 10 * s)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparkleStarPainter old) => old.color != color;
}
