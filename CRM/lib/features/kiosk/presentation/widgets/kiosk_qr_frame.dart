import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';

/// The tile's hairline: the pinned QR module ink at the light theme's hairline
/// alpha. Derived from the module colour rather than [DesignConstants.line]
/// on purpose — the theme hairline flips to a near-white in dark mode and
/// would vanish on this always-white tile.
const double _kQuietZoneHairlineAlpha = 0.09;

/// The white tile every kiosk QR sits in (mockup `.qr-frame`): a fixed quiet
/// zone, a hairline, the soft card lift, and a rounded corner.
///
/// **Deliberately theme-independent.** A QR's contrast is functional, not
/// decorative — scanners expect dark modules on a light quiet zone and many
/// fail on an inverted code — so this tile pins to
/// [DesignConstants.kioskQrQuietZone] in every theme instead of following
/// `surface`. It is the ONE place that treatment lives; a QR surface elsewhere
/// in the kiosk composes this rather than restating the colours.
///
/// Pass [accent] for the download QR's sapphire-tinted border (mockup
/// `.qr-frame.download`); the neutral hairline is the default.
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
