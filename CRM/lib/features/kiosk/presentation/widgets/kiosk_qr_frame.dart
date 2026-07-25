import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The tile's hairline: the pinned QR module ink at the light theme's hairline
/// alpha. Derived from the module colour rather than [DesignConstants.line]
/// because the theme hairline flips near-white in dark mode and would vanish
/// on this always-white tile.
const double _kQuietZoneHairlineAlpha = 0.09;

/// The white tile every kiosk QR sits in: a fixed quiet zone, a hairline, the
/// soft card lift, and a rounded corner.
///
/// Deliberately theme-independent: a QR's contrast is functional, and many
/// scanners fail on an inverted code, so this tile pins to
/// [DesignConstants.kioskQrQuietZone] in EVERY theme instead of following
/// `surface`. It is the ONE place that treatment lives — never "fix" a kiosk
/// QR back onto the theme tokens.
///
/// Pass [accent] for the download QR's sapphire-tinted border.
class KioskQrFrame extends StatelessWidget {
  final Widget child;
  final bool accent;
  final double radius;

  /// The white margin drawn around the code. The download QR passes a smaller
  /// value because `QrImageView` already draws its own quiet zone inside.
  final double padding;

  const KioskQrFrame({
    super.key,
    required this.child,
    this.accent = false,
    this.radius = DesignConstants.radiusCard,
    this.padding = DesignConstants.paddingSmall,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: DesignConstants.kioskQrQuietZone,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: accent
              ? DesignConstants.primaryColor.withValues(alpha: 0.28)
              : DesignConstants.kioskQrModule
                  .withValues(alpha: _kQuietZoneHairlineAlpha),
        ),
        boxShadow: DesignConstants.cardShadow,
      ),
      child: child,
    );
  }
}
