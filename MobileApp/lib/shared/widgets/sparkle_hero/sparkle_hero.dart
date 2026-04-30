import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/design_constants.dart';

/// Sparkles scattered around a hero accent — porting the loyalty-loop
/// "+160 PTS" effect from LandingPage/onepager/onepager.jsx. Each entry is
/// (size, dx, dy, opacity) where dx/dy are pixel offsets from the center
/// of the text block.
const _kSparkles = <(double size, double dx, double dy, double opacity)>[
  // Outer ring — large anchors pushed out to the screen edges.
  (14, -150, -40, 0.85),
  (12, 156, 36, 0.80),
  (10, 152, -48, 0.60),
  (10, -156, 28, 0.55),
  // Edge accents on the far horizontal flanks.
  (8, -170, -8, 0.55),
  (8, 168, -16, 0.65),
  (8, 0, -62, 0.50),
  (8, -70, 60, 0.55),
  (8, 76, 62, 0.60),
  // Mid-field scatter spaced wider.
  (6, 110, -38, 0.45),
  (6, -116, -50, 0.40),
  (6, 130, 8, 0.55),
  (6, -128, 60, 0.45),
  (6, 172, 22, 0.55),
  // Tiny atmospheric specks across the band.
  (4, 50, -48, 0.40),
  (4, -56, 38, 0.40),
  (4, 140, -30, 0.45),
  (4, -148, -28, 0.40),
  (4, 24, 70, 0.45),
  (3, 96, -58, 0.35),
  (3, -100, 18, 0.35),
  (3, 0, 78, 0.40),
];

/// Three-line hero block with sparkles scattered around the orange accent.
/// Top and bottom labels render as small-cap eyebrows; the center accent
/// is the focal point in primaryColor at big1_5.
///
/// Examples:
///   SparkleHero(top: 'YOU EARNED', accent: '3,400', bottom: 'POINTS')
///   SparkleHero(top: 'YOU HAVE A', accent: '3 WEEK', bottom: 'STREAK')
class SparkleHero extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final eyebrow = DesignConstants.pSmall.copyWith(
      color: DesignConstants.text2nd,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.24 * (DesignConstants.pSmall.fontSize ?? 11),
    );
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: DesignConstants.screenHorizontalPadding,
        vertical: DesignConstants.paddingBig,
      ),
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          for (final s in _kSparkles)
            Transform.translate(
              offset: Offset(s.$2, s.$3),
              child: _Sparkle(size: s.$1, opacity: s.$4),
            ),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            spacing: DesignConstants.spacingSmall,
            children: [
              Text(top, style: eyebrow, textAlign: TextAlign.center),
              Text(
                accent,
                style: DesignConstants.big1_5.copyWith(
                  color: DesignConstants.primaryColor,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              Text(bottom, style: eyebrow, textAlign: TextAlign.center),
            ],
          ),
        ],
      ),
    );
  }
}

class _Sparkle extends StatelessWidget {
  const _Sparkle({required this.size, required this.opacity});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _SparklePainter(opacity: opacity)),
    );
  }
}

class _SparklePainter extends CustomPainter {
  _SparklePainter({required this.opacity});

  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final paint = Paint()
      ..color = DesignConstants.primaryColor.withValues(alpha: opacity);
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
  bool shouldRepaint(covariant _SparklePainter old) =>
      old.opacity != opacity;
}
