import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';

/// C3 — the billing service did not answer, so the money half is a retry.
///
/// WARM, never red: nothing has been charged, nothing is lost, and the lineup
/// on the left is intact — this is "try that again", not a verdict. Red here
/// would read as a refused card, which is a completely different fact about
/// the payer.
class WizardReviewChargesFailed extends StatelessWidget {
  final VoidCallback onRetry;

  const WizardReviewChargesFailed({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final copy = MembershipFlowTheme.copyOf(context);
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.yellowDark,
        borderRadius: BorderRadius.circular(DesignConstants.radiusCard),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DesignConstants.spacingMedium,
        children: [
          Icon(
            Symbols.warning_sharp,
            size: DesignConstants.iconSizeLarge,
            weight: DesignConstants.iconWeight,
            color: DesignConstants.okYellow,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: DesignConstants.spacingMedium,
              children: [
                Text(
                  WizardReviewCopy.chargesFailedTitle,
                  style: scale.label,
                ),
                Text(
                  WizardReviewCopy.chargesFailedBody,
                  style: scale.caption.copyWith(
                    color: DesignConstants.text2nd,
                  ),
                ),
                AppOutlineButton(
                  text: copy.retryAction,
                  onPressed: onRetry,
                  textStyle: scale.buttonOutlineLabel,
                  icon: Icon(
                    Symbols.refresh_sharp,
                    size: DesignConstants.iconSizeSmall,
                    weight: DesignConstants.iconWeight,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
