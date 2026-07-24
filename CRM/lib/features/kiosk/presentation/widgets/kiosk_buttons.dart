import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';

/// The kiosk's button set — the shared [AppPrimaryButton] / [AppOutlineButton]
/// wearing the kiosk display scale instead of the admin defaults, plus the
/// kiosk-only ghost (escape) tier.
///
/// The kiosk is read and pressed from standing distance, so its labels and hit
/// boxes run a step larger (mockup `.btn-primary` 19px / 18x34,
/// `.btn-outline` 17px / 15x30, `.btn-ghost` 17px / 13x18) than the
/// 13px / 16x8 admin buttons. These wrappers are the ONLY place those tokens
/// are applied: every kiosk button goes through them, so the whole set scales
/// together and can never desync, and no kiosk call site ever restates a size.
/// The admin surfaces keep the base buttons untouched.
///
/// The ladder, loudest first: [KioskPrimaryButton] (gradient) >
/// [KioskOutlineButton] (2px ink) > [KioskGhostButton] (nothing). A primary
/// may borrow the outline's SIZE (`compact: true`) without leaving its tier —
/// see [KioskPrimaryButton].

/// The kiosk's primary action — the brand gradient CTA at kiosk scale.
///
/// Pass [compact] where a filled button has to sit BESIDE a secondary one and
/// must not out-shout it (the home's "Get it", which shares a screen with
/// "New here? Sign up"). Compact keeps the gradient — it is still the primary
/// tier — and only drops to the OUTLINE button's own metrics, reusing that
/// token rather than declaring a third size, so the two can never drift apart
/// and the ramp still moves as one set.
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

/// The kiosk's secondary action (Done / Okay / Sign up) — the ink-outlined
/// button at kiosk scale.
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

/// The kiosk's ESCAPE tier (mockup `.btn-ghost`) — no border, no fill, a muted
/// label behind a back chevron. The quietest rung of the ladder, and the only
/// one used for LEAVING a flow: an escape hatch must be findable without ever
/// competing with the action the member came to take.
///
/// It is a bare [TextButton] rather than a wrapped [AppOutlineButton] on
/// purpose — the whole point of the tier is that it has no chrome, so there is
/// no border/fill to strip off a shared button.
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
