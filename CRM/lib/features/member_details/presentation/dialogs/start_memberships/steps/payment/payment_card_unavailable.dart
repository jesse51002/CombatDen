import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/network/stripe_account_context.dart';
import 'package:crm/core/state/selected_gym.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_detail_group.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';

/// C4 — this gym's Stripe connected account is not usable, so no card can be
/// taken on this device.
///
/// It FAILS CLOSED and says so: no card field, no half-working form, and no
/// pretence that pressing Pay might work. Cash stays open above it, so the run
/// is still completable today — which is the whole reason this replaces the
/// two card groups rather than the whole step.
class WizardPaymentCardUnavailable extends StatelessWidget {
  final String payerFirstName;

  /// Whether the payer has a saved card at all. With none, the run genuinely
  /// cannot take money today and the line under the retry says so.
  final bool hasSavedCard;

  const WizardPaymentCardUnavailable({
    super.key,
    required this.payerFirstName,
    required this.hasSavedCard,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final copy = MembershipFlowTheme.copyOf(context);
    return FlowDetailGroup(
      eyebrow: WizardPaymentCopy.cardEyebrow,
      children: [
        Container(
          padding: const EdgeInsets.all(DesignConstants.paddingSmall),
          decoration: BoxDecoration(
            color: DesignConstants.yellowDark,
            borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingMedium,
            children: [
              Icon(
                Symbols.credit_card_off_sharp,
                size: DesignConstants.iconSizeLarge,
                weight: DesignConstants.iconWeight,
                color: DesignConstants.okYellow,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  spacing: DesignConstants.spacingSmall,
                  children: [
                    Text(
                      WizardPaymentCopy.cardEntryTitle,
                      style: scale.label,
                    ),
                    Text(
                      WizardPaymentCopy.cardEntryBody,
                      style: scale.caption.copyWith(
                        color: DesignConstants.text2nd,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: AppOutlineButton(
            text: copy.retryAction,
            // Re-applies the gym's connected account to Stripe.js. The seam
            // keeps the last error, so retrying the SAME account is a real
            // attempt rather than a no-op.
            onPressed: () => stripeAccountContext.apply(
              selectedGym.stripeAccountId,
            ),
            textStyle: scale.buttonOutlineLabel,
            icon: Icon(
              Symbols.refresh_sharp,
              size: DesignConstants.iconSizeSmall,
              weight: DesignConstants.iconWeight,
            ),
          ),
        ),
        if (!hasSavedCard)
          Text(
            WizardPaymentCopy.noSavedCard(payerFirstName),
            style: scale.caption.copyWith(color: DesignConstants.okYellow),
          ),
      ],
    );
  }
}
