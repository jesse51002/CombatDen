import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';

/// The kiosk's button set — the shared [AppPrimaryButton] / [AppOutlineButton]
/// at the kiosk's larger standing-distance scale, plus the kiosk-only ghost
/// (escape) tier. The ONLY place the kiosk button tokens are applied, so the
/// whole set scales as one and no call site restates a size. Loudest first:
/// [KioskPrimaryButton] > [KioskOutlineButton] > [KioskGhostButton].

/// The kiosk's primary action — the brand gradient CTA at kiosk scale.
///
/// Pass [compact] where a filled button sits BESIDE a secondary one and must
/// not out-shout it. It keeps the gradient and reuses the OUTLINE button's own
/// metrics rather than declaring a third size, so the two can't drift apart.
class KioskPrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;

  /// Size this filled button to the secondary rung ([KioskOutlineButton]'s
  /// label + padding) instead of the loud primary rung.
  final bool compact;

  const KioskPrimaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return AppPrimaryButton(
      text: text,
      onPressed: onPressed,
      textStyle: compact
          ? DesignConstants.kioskButtonOutlineLabel
          : DesignConstants.kioskButtonPrimaryLabel,
      padding: compact
          ? DesignConstants.kioskButtonOutlinePadding
          : DesignConstants.kioskButtonPrimaryPadding,
    );
  }
}

/// The kiosk's secondary action (Done / Okay / the home's "Start Trial /
/// Membership") — the ink-outlined button at kiosk scale.
class KioskOutlineButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;

  const KioskOutlineButton({
    super.key,
    required this.text,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return AppOutlineButton(
      text: text,
      onPressed: onPressed,
      textStyle: DesignConstants.kioskButtonOutlineLabel,
      padding: DesignConstants.kioskButtonOutlinePadding,
    );
  }
}

/// The kiosk's ESCAPE tier — the quietest rung, and the only one used for
/// LEAVING a flow: an escape hatch must be findable without competing with the
/// action the member came to take. A bare [TextButton], not a wrapped
/// [AppOutlineButton], since the tier's point is having no chrome.
class KioskGhostButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;

  const KioskGhostButton({
    super.key,
    required this.text,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: DesignConstants.text2nd,
        padding: DesignConstants.kioskButtonGhostPadding,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingSmall,
        children: [
          Icon(
            Symbols.chevron_left_sharp,
            size: DesignConstants.iconSizeMedium,
            weight: DesignConstants.iconWeight,
            color: DesignConstants.text2nd,
          ),
          Text(text, style: DesignConstants.kioskButtonGhostLabel),
        ],
      ),
    );
  }
}
