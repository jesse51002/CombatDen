/// The desk wizard's RAIL — one rung per named stage of the run.
///
/// It is deliberately not the cubit's spine. The spine is `5 + N` SCREENS
/// (the plans step is walked once per training person); the rail is the six
/// things staff are being asked for, so a three-person family does not draw
/// eight rungs of which three say the same word. How far through the screens
/// the run actually is belongs to the topbar's `Step N of M`, which counts the
/// real spine — the old indicator's hardcoded `substepCount: 5` against a real
/// `2N + 3` is the failure this split exists to prevent.
library;

import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_step.dart';

/// The always-done rung the add-member flow prepends: the member exists
/// already, and the run staff are looking at is its tail.
const String kWizardAddedRung = 'Member added';

const List<String> _stages = <String>[
  'Who',
  'Plans',
  'Waivers',
  'Review',
  'Payment',
  'Done',
];

/// The rungs this run draws. A run nobody owes a signature for has no waivers
/// rung — an unreachable stage on the rail is a promise the flow does not
/// keep.
List<String> wizardRailSteps({
  required bool hasWaivers,
  required bool showAddMemberGroup,
}) =>
    <String>[
      if (showAddMemberGroup) kWizardAddedRung,
      for (final stage in _stages)
        if (hasWaivers || stage != _stages[2]) stage,
    ];

/// Which rung [step] lights.
int wizardRailIndex(
  MembershipWizardStep step, {
  required bool hasWaivers,
  required bool showAddMemberGroup,
}) {
  final lead = showAddMemberGroup ? 1 : 0;
  final waiverSlot = hasWaivers ? 1 : 0;
  return lead +
      switch (step) {
        MembershipWizardStep.who => 0,
        MembershipWizardStep.plans => 1,
        MembershipWizardStep.waivers => 2,
        MembershipWizardStep.reviewCharges => 2 + waiverSlot,
        MembershipWizardStep.payment => 3 + waiverSlot,
        MembershipWizardStep.results => 4 + waiverSlot,
      };
}
