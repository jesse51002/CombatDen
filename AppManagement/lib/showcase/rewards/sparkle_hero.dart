import 'package:flutter/material.dart';

import 'package:app_management/showcase/showcase_tokens.dart';
import 'package:theme_flutter/theme/animation/celebration_timings.dart';

/// Showcase clone of MobileApp's `SparkleHero`: sparkles scattered around a
/// hero accent (the "YOU EARNED / 3,400 / POINTS" block). Each entry is
/// (size, dx, dy, opacity); dx/dy are pixel offsets from the center.
const _kSparkles = <(double size, double dx, double dy, double opacity)>[
  (14, -150, -40, 0.85),
  (12, 156, 36, 0.80),
  (10, 152, -48, 0.60),
  (10, -156, 28, 0.55),
  (8, -170, -8, 0.55),
  (8, 168, -16, 0.65),
  (8, 0, -62, 0.50),
  (8, -70, 60, 0.55),
  (8, 76, 62, 0.60),
  (6, 110, -38, 0.45),
  (6, -116, -50, 0.40),
  (6, 130, 8, 0.55),
  (6, -128, 60, 0.45),
  (6, 172, 22, 0.55),
  (4, 50, -48, 0.40),
  (4, -56, 38, 0.40),
  (4, 140, -30, 0.45),
  (4, -148, -28, 0.40),
  (4, 24, 70, 0.45),
  (3, 96, -58, 0.35),
  (3, -100, 18, 0.35),
  (3, 0, 78, 0.40),
];

class SparkleHero extends StatefulWidget {
  const SparkleHero({
    super.key,
    required this.top,
    required this.accent,
    required this.bottom,
  });

  final String top;
  final String accent;
  final String bottom;

  @override
  State<SparkleHero> createState() => _SparkleHeroState();
}

class _SparkleHeroState extends State<SparkleHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: CelebrationTimings.sparkleWindow,
  );

  late final List<int> _order = _orderByDistance();

  List<int> _orderByDistance() {
    final indexed = List<int>.generate(_kSparkles.length, (i) => i);
    indexed.sort((a, b) {
      final sa = _kSparkles[a];
      final sb = _kSparkles[b];
      final da = sa.$2 * sa.$2 + sa.$3 * sa.$3;
      final db = sb.$2 * sb.$2 + sb.$3 * sb.$3;
      return da.compareTo(db);
    });
    return indexed;
  }

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = ShowcaseTokens.primaryColor;
    final eyebrow = ShowcaseTokens.pSmall.copyWith(
      color: ShowcaseTokens.text2nd,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.24 * (ShowcaseTokens.pSmall.fontSize ?? 11),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ShowcaseTokens.screenHorizontalPadding,
        vertical: ShowcaseTokens.paddingBig,
      ),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              for (var rank = 0; rank < _kSparkles.length; rank++)
                _animatedSparkle(rank, primary),
              _accentBlock(primary, eyebrow),
            ],
          );
        },
      ),
    );
  }

  Widget _animatedSparkle(int rank, Color color) {
    final s = _kSparkles[_order[rank]];
    final n = _kSparkles.length;
    final stagger = (rank / n) * 0.7;
    final localT = ((_ctrl.value - stagger) / 0.35).clamp(0.0, 1.0);
    final eased = Curves.easeOutQuart.transform(localT);
    return Transform.translate(
      offset: Offset(s.$2, s.$3),
      child: Opacity(
        opacity: eased * s.$4,
        child: Transform.scale(
          scale: 0.5 + 0.5 * eased,
          child: _Sparkle(size: s.$1, color: color),
        ),
      ),
    );
  }

  Widget _accentBlock(Color primary, TextStyle eyebrow) {
    final t = Curves.easeOutQuart.transform(_ctrl.value.clamp(0.0, 1.0));
    return Opacity(
      opacity: t,
      child: Transform.scale(
        scale: 0.92 + 0.08 * t,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: ShowcaseTokens.spacingSmall,
          children: [
            Text(widget.top, style: eyebrow, textAlign: TextAlign.center),
            Text(
              widget.accent,
              style: ShowcaseTokens.big1_5.copyWith(
                color: primary,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            Text(widget.bottom, style: eyebrow, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _Sparkle extends StatelessWidget {
  const _Sparkle({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _SparklePainter(color: color)),
    );
  }
}

class _SparklePainter extends CustomPainter {
  _SparklePainter({required this.color});

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
  bool shouldRepaint(covariant _SparklePainter old) => old.color != color;
}
