import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_who_for.dart';

/// The pinned identity band on the plans step.
///
/// At the desk "who pays" and "who this is for" are different people and BOTH
/// are correctness controls — a parent picking three memberships in a row must
/// never buy the wrong one for the wrong child — so the step names both. When
/// the person picking IS the payer there is only one fact, and repeating it
/// twice would teach staff to stop reading the band at all.
class PlansIdentityStrip extends StatelessWidget {
  final String payerName;
  final String personName;
  final bool personIsPayer;

  const PlansIdentityStrip({
    super.key,
    required this.payerName,
    required this.personName,
    required this.personIsPayer,
  });

  @override
  Widget build(BuildContext context) {
    if (personIsPayer) {
      return FlowWhoFor(
        eyebrow: WizardPlansCopy.pickingForPayerEyebrow,
        name: personName,
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: DesignConstants.spacingMedium,
      children: [
        Flexible(
          child: FlowWhoFor(
            eyebrow: WizardPlansCopy.payingForAllEyebrow,
            name: payerName,
          ),
        ),
        Flexible(
          child: FlowWhoFor(
            eyebrow: WizardPlansCopy.pickingForEyebrow,
            name: personName,
          ),
        ),
      ],
    );
  }
}
