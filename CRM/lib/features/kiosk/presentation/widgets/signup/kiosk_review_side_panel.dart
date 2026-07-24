import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/core/utils/money.dart';
import 'package:crm/features/kiosk/bloc/kiosk_signup_state.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_buy_row.dart';
import 'package:crm/features/kiosk/presentation/widgets/signup/kiosk_plan_labels.dart';
import 'package:crm/shared/widgets/class_row/instructor_avatar.dart';

/// The review's left half: who this is, what they picked, and what they have
/// already signed.
///
/// The signed row is the reason this panel exists at all. A member who typed
/// their name into a legal document two screens ago should see it acknowledged
/// before they hand over a card — `Signed today by <name>` is the receipt for
/// the thing that has no receipt.
class KioskReviewSidePanel extends StatelessWidget {
  final KioskSignupState state;

  const KioskReviewSidePanel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final person = state.activePerson;
    final plan = state.selectedPlan;
    final price = plan?.activePrice;
    return Container(
      padding: const EdgeInsets.all(DesignConstants.paddingSmall),
      decoration: BoxDecoration(
        color: DesignConstants.surface,
        borderRadius: BorderRadius.circular(DesignConstants.radiusCard),
        border: Border.all(color: DesignConstants.line),
        boxShadow: DesignConstants.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: DesignConstants.spacingLarge,
        children: [
          Text('YOU', style: DesignConstants.kioskEyebrow),
          _WhoRow(
            name: '${person.firstName} ${person.lastName}'.trim(),
            email: person.email,
          ),
          Text('YOUR MEMBERSHIP', style: DesignConstants.kioskEyebrow),
          if (plan != null)
            KioskBuyRow(
              name: plan.planName,
              rule: kioskPlanRuleLabel(plan),
              imageUrl: plan.imageUrl,
              amount: price == null
                  ? null
                  : formatMinorUnits(price.price, currency: 'USD'),
            ),
          for (final signed in state.signedWaivers)
            KioskBuyRow(
              name: signed.name,
              rule: 'Signed today by ${signed.signerName}',
            ),
        ],
      ),
    );
  }
}

class _WhoRow extends StatelessWidget {
  final String name;
  final String email;

  const _WhoRow({required this.name, required this.email});

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: DesignConstants.spacingMedium,
      children: [
        InstructorAvatar(name: name, diameter: DesignConstants.iconSizeBig),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            spacing: DesignConstants.spacingSmall,
            children: [
              Text(
                name,
                style: DesignConstants.kioskName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                email,
                style: DesignConstants.kioskCaption.copyWith(
                  color: DesignConstants.text2nd,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
