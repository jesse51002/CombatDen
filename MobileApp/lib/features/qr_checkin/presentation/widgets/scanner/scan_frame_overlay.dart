import 'package:flutter/material.dart';
import 'package:mobile_app/core/design_constants.dart';

// Per-screen layout math (CLAUDE.md _k carve-out): the reticle is an
// intrinsic camera-viewfinder size, not a fungible design token.
const double _kReticleSize = 260;
const double _kReticleBorder = 3;

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

class _Reticle extends StatelessWidget {
  const _Reticle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _kReticleSize,
      height: _kReticleSize,
      decoration: BoxDecoration(
        border: Border.all(
          color: DesignConstants.primaryColor,
          width: _kReticleBorder,
        ),
        borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
      ),
    );
  }
}
