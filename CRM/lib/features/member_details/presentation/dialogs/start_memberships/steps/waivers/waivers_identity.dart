import 'package:flutter/material.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';
import 'package:crm/features/membership_flow/presentation/chrome/flow_who_for.dart';

/// The waivers step's pinned identity band: who PAYS for the run, and whose
/// signature is being taken right now.
///
/// Two chips, because on this one step they are usually two different humans —
/// a parent signing on a child's behalf — and a step that names only one of
/// them leaves staff guessing which. Where the signer IS the payer the second
/// chip collapses: the same name twice, under two eyebrows, reads as two
/// people.
class WizardWaiversIdentity extends StatelessWidget {
  final String payerName;

  /// The member the signature binds. Null (or the payer again) leaves the
  /// payer's chip standing alone.
  final String? signingForName;

  const WizardWaiversIdentity({
    super.key,
    required this.payerName,
    this.signingForName,
  });

  @override
  Widget build(BuildContext context) {
    final signer = signingForName?.trim() ?? '';
    final payer = FlowWhoFor(
      eyebrow: WizardPlansCopy.payingForAllEyebrow,
      name: payerName,
    );
    if (signer.isEmpty || signer == payerName.trim()) return payer;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      spacing: DesignConstants.spacingMedium,
      children: [
        payer,
        FlowWhoFor(
          eyebrow: WizardWaiversCopy.signingForEyebrow,
          name: signer,
        ),
      ],
    );
  }
}
