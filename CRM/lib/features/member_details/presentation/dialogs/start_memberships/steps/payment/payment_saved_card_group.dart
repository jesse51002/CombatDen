import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/data/models/card_on_file.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';
import 'package:crm/features/membership_flow/config/membership_flow_theme.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_detail_group.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_card_chip.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_consent_check.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_inline_notice.dart';
import 'package:crm/shared/widgets/app_outline_button.dart';

/// The payer's saved default card — what settles today unless cash is on, and
/// the only card a recurring membership can ever bill.
///
/// The tick is a STATED FACT, not a choice: with cash off and a card on file,
/// that card is what pays, and a checkbox that turned it off would imply a
/// third way to settle that does not exist. The warning is said BEFORE the
/// control is used, because replacing this card re-bills every recurring
/// membership the payer already holds, not just today's — so it only appears
/// where there is a card to replace.
class WizardPaymentSavedCardGroup extends StatelessWidget {
  final String payerFirstName;
  final CardOnFile? card;
  final VoidCallback onUpdateCard;

  const WizardPaymentSavedCardGroup({
    super.key,
    required this.payerFirstName,
    required this.card,
    required this.onUpdateCard,
  });

  @override
  Widget build(BuildContext context) {
    final scale = MembershipFlowTheme.of(context);
    final saved = card;
    return FlowDetailGroup(
      eyebrow: WizardPaymentCopy.cardOnFileEyebrow,
      children: [
        if (saved == null)
          Text(
            WizardPaymentCopy.noSavedCard(payerFirstName),
            style: scale.body.copyWith(color: DesignConstants.okYellow),
          )
        else
          FlowConsentCheck(
            value: true,
            // Inert on purpose — see the class doc.
            onChanged: (_) {},
            label: WizardPaymentCopy.savedCardLabel(payerFirstName),
            note: WizardPaymentCopy.savedCardNote,
          ),
        Row(
          spacing: DesignConstants.spacingMedium,
          children: [
            if (saved != null) ...[
              FlowCardChip(brand: saved.brand, last4: saved.lastFour),
              // The expiry, beside the chip rather than inside it: a member
              // reading the kiosk's chip needs to know WHICH card, and staff
              // about to charge it need to know it has not expired.
              Text(
                WizardPaymentCopy.cardExpiry(saved.expMonth, saved.expYear),
                style: scale.caption.copyWith(
                  color: DesignConstants.text2nd,
                ),
              ),
            ],
            const Spacer(),
            AppOutlineButton(
              text: WizardPaymentCopy.updateCard,
              onPressed: onUpdateCard,
              textStyle: scale.buttonOutlineLabel,
              icon: Icon(
                Symbols.credit_card_sharp,
                size: DesignConstants.iconSizeSmall,
                weight: DesignConstants.iconWeight,
              ),
            ),
          ],
        ),
        if (saved != null)
          FlowInlineNotice(
            message: WizardPaymentCopy.updateCardWarning(payerFirstName),
            // Info, not warm: nothing is wrong and nothing needs deciding
            // here. It states the blast radius of editing a default card, and
            // the warm treatment read as an accusation beside a card form.
            tone: FlowNoticeTone.info,
          ),
      ],
    );
  }
}
