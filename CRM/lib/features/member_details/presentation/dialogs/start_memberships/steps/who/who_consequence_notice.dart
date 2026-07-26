import 'package:flutter/material.dart';

import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_consequence.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';
import 'package:crm/features/membership_flow/presentation/widgets/flow_inline_notice.dart';

/// What the last destructive control on the roster actually dropped, stated
/// after the fact.
///
/// The row's own warning line says what unticking WOULD cost; this says what
/// it DID. Both are needed: the untick commits on the tap (a confirm dialog on
/// a control this cheap is a second trap), so without this the drop is
/// invisible — which is exactly what the old wizard did three different ways.
///
/// It carries no dismiss of its own: every roster control that can follow it
/// either replaces the consequence or clears it, so the notice is answered by
/// the next thing staff do rather than by a button that only tidies up.
class WhoConsequenceNotice extends StatelessWidget {
  final MembershipWizardConsequence consequence;

  const WhoConsequenceNotice({super.key, required this.consequence});

  @override
  Widget build(BuildContext context) {
    return FlowInlineNotice(message: _message);
  }

  String get _message {
    final name = consequence.memberName.trim();
    final first = name.isEmpty ? name : name.split(' ').first;
    return switch (consequence.kind) {
      MembershipWizardConsequenceKind.payerSwitch =>
        WizardWhoCopy.payerSwitchDrop(
          payerName: name,
          memberships: consequence.membershipsDropped,
          people: consequence.peopleDropped,
        ),
      MembershipWizardConsequenceKind.untickPerson =>
        WizardWhoCopy.untickedDrop(
          firstName: first,
          memberships: consequence.membershipsDropped,
        ),
      MembershipWizardConsequenceKind.removeMembership =>
        WizardWhoCopy.membershipRemovedDrop(
          firstName: first,
          memberships: consequence.membershipsDropped,
          people: consequence.peopleDropped,
        ),
    };
  }
}
