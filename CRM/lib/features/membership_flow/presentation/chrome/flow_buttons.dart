import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';
import 'package:crm/shared/widgets/app_primary_button.dart';

/// The membership flow's button set — the shared [AppPrimaryButton] /
/// [AppOutlineButton] at the SURFACE's own scale, plus the flow-only ghost
/// (escape) tier. The ONLY place a flow button's label style and box are
/// applied, so the whole set scales as one and no call site restates a size.
/// Loudest first: [FlowPrimaryButton] > [FlowOutlineButton] >
/// [FlowGhostButton].
///
/// Each reads its metrics off [MembershipFlowTheme], so one surface's buttons
/// can never be re-scaled without the other's — the failure this set exists to
/// prevent is a screen whose headline moved and whose buttons did not.
///
/// **The two sets are a deliberate split, not a duplicate.** This one reads
/// the SCALE, so it can render at either surface's size; the kiosk's own
/// `kiosk_buttons.dart` pins the `kiosk*` tokens directly, for the lanes that
/// are kiosk-only and never render at a second scale (the check-in lane, the
/// terminal screens, the signup's own kiosk-only overlays). Both are thin
/// wrappers over the same shared `AppPrimaryButton` / `AppOutlineButton`, so
/// the split is wiring rather than logic, and under
/// `MembershipFlowScale.kiosk()` the two resolve to identical metrics.

/// The flow's primary action — the brand gradient CTA at the surface's scale.
///
/// Pass [compact] where a filled button sits BESIDE a secondary one and must
/// not out-shout it. It keeps the gradient and reuses the OUTLINE button's own
/// metrics rather than declaring a third size, so the two can't drift apart.
class FlowPrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;

  /// Size this filled button to the secondary rung ([FlowOutlineButton]'s
  /// label + padding) instead of the loud primary rung.
  final bool compact;

  const FlowPrimaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    return AppPrimaryButton(
      text: text,
      onPressed: onPressed,
      textStyle:
          compact ? scale.buttonOutlineLabel : scale.buttonPrimaryLabel,
      padding:
          compact ? scale.buttonOutlinePadding : scale.buttonPrimaryPadding,
    );
  }
}

/// The flow's secondary action (Back / Skip / "Try another card") — the
/// ink-outlined button at the surface's scale.
class FlowOutlineButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;

  const FlowOutlineButton({
    super.key,
    required this.text,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    return AppOutlineButton(
      text: text,
      onPressed: onPressed,
      textStyle: scale.buttonOutlineLabel,
      padding: scale.buttonOutlinePadding,
    );
  }
}

/// The flow's ESCAPE tier — the quietest rung, and the only one used for
/// LEAVING a flow: an escape hatch must be findable without competing with the
/// action the member came to take. A bare [TextButton], not a wrapped
/// [AppOutlineButton], since the tier's point is having no chrome.
class FlowGhostButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;

  const FlowGhostButton({
    super.key,
    required this.text,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: DesignConstants.text2nd,
        padding: scale.buttonGhostPadding,
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
          Text(text, style: scale.buttonGhostLabel),
        ],
      ),
    );
  }
}
