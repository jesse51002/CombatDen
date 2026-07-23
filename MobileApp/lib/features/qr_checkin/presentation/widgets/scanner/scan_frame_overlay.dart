import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';

// Per-screen layout math (CLAUDE.md _k carve-out): the reticle and its corner
// brackets are intrinsic camera-viewfinder geometry, not fungible design
// tokens.
const double _kReticleSize = 260;
const double _kBracketStroke = 4;
const double _kBracketArm = 44;
const double _kBracketRadius = 20;

/// The scanner's viewfinder overlay: a title + hint on a legible scrim above a
/// centered square reticle that frames where to aim the QR code. Drawn on top
/// of the live [MobileScanner] preview; purely decorative (no interaction).
class ScanFrameOverlay extends StatelessWidget {
  const ScanFrameOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: DesignConstants.spacingBig,
      children: const [
        _ScannerTitle(),
        _Reticle(),
        _ScannerHint(),
      ],
    );
  }
}

class _ScannerTitle extends StatelessWidget {
  const _ScannerTitle();

  @override
  Widget build(BuildContext context) {
    return _Scrim(
      child: Text(
        "Scan the gym's check-in code",
        textAlign: TextAlign.center,
        style: DesignConstants.h1.copyWith(color: DesignConstants.text),
      ),
    );
  }
}

class _ScannerHint extends StatelessWidget {
  const _ScannerHint();

  @override
  Widget build(BuildContext context) {
    return _Scrim(
      child: Text(
        'Point your camera at the code on the front desk',
        textAlign: TextAlign.center,
        style: DesignConstants.p.copyWith(color: DesignConstants.text2nd),
      ),
    );
  }
}

/// A translucent pill behind text so it stays readable over the live camera.
class _Scrim extends StatelessWidget {
  const _Scrim({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DesignConstants.backgroundColor.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(DesignConstants.radiusSmall),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: DesignConstants.paddingSmall,
          vertical: DesignConstants.spacingMedium,
        ),
        child: child,
      ),
    );
  }
}

/// A square framed by four rounded corner brackets — the QR-scanner idiom that
/// tells the eye "line the code up inside here". Drawn in the brand primary
/// over the live camera.
class _Reticle extends StatelessWidget {
  const _Reticle();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _kReticleSize,
      height: _kReticleSize,
      child: CustomPaint(
        painter: _BracketPainter(color: DesignConstants.primaryColor),
      ),
    );
  }
}

class _BracketPainter extends CustomPainter {
  _BracketPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _kBracketStroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final i = _kBracketStroke / 2;
    final left = i;
    final top = i;
    final right = size.width - i;
    final bottom = size.height - i;
    const arm = _kBracketArm;
    const r = _kBracketRadius;

    final path = Path()
      // Top-left.
      ..moveTo(left, top + arm)
      ..lineTo(left, top + r)
      ..quadraticBezierTo(left, top, left + r, top)
      ..lineTo(left + arm, top)
      // Top-right.
      ..moveTo(right - arm, top)
      ..lineTo(right - r, top)
      ..quadraticBezierTo(right, top, right, top + r)
      ..lineTo(right, top + arm)
      // Bottom-right.
      ..moveTo(right, bottom - arm)
      ..lineTo(right, bottom - r)
      ..quadraticBezierTo(right, bottom, right - r, bottom)
      ..lineTo(right - arm, bottom)
      // Bottom-left.
      ..moveTo(left + arm, bottom)
      ..lineTo(left + r, bottom)
      ..quadraticBezierTo(left, bottom, left, bottom - r)
      ..lineTo(left, bottom - arm);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BracketPainter old) => old.color != color;
}
