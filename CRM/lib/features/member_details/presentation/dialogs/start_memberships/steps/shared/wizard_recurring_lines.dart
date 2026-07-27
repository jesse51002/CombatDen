/// What this run adds to the payer's recurring bill, line by line.
///
/// Read once and rendered twice — on the review's breakdown and again in the
/// payment step's "what pay will do" echo — so the two screens can never quote
/// a different figure for the same cart. A membership an earlier attempt
/// already created is skipped: the next charge does not cover it.
library;

import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_state.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_views.dart';

/// One recurring membership this run starts, named by person and plan.
typedef WizardRecurringLine = ({String label, int amount});

/// One line per recurring membership in the cart. A one-off pack does not
/// recur for the child who got it, and implying it does is the small lie that
/// produces a phone call.
List<WizardRecurringLine> wizardRecurringLines(MembershipWizardState state) {
  final lines = <WizardRecurringLine>[];
  for (final person in state.trainingPeople) {
    for (final draft in state.draftsFor(person.memberId)) {
      if (draft.plan.planType != PlanType.recurring) continue;
      if (state.alreadyStarted(person.memberId, draft.plan.planId)) continue;
      final money = wizardLineMoney(state, draft);
      if (money == null) continue;
      lines.add((
        label: WizardReviewCopy.personPlan(
          person.firstName,
          draft.plan.planName,
        ),
        amount: money.netMinorUnits,
      ));
    }
  }
  return lines;
}

/// What those lines come to — what the run ADDS each cycle.
int wizardRecurringAddedMinor(MembershipWizardState state) =>
    wizardRecurringLines(state)
        .fold<int>(0, (sum, line) => sum + line.amount);
