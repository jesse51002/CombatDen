/// Who and what each row of the receipt is about.
///
/// The response names a member id and a plan id; the receipt names a PERSON
/// and a PLAN, because "b3f1… · 9ac7…" is not a thing anybody can check
/// against a bank statement. Both lookups degrade rather than invent: a row
/// the roster cannot explain still prints, still marked, because a membership
/// the backend acted on must never disappear from its own receipt.
library;

import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_derived.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_state.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_result_item.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/wizard_copy.dart';

/// "Marcus Bell · 10-Class Pack" for one result row.
String wizardResultLabel(
  MembershipWizardState state,
  MemberMembershipsStartResultItem item,
) {
  final name = _memberName(state, item.memberId);
  final plan = _planName(state, item.planId);
  if (name.isEmpty) return plan;
  if (plan.isEmpty) return name;
  return WizardReviewCopy.personPlan(name, plan);
}

/// The member's own name for the row's semantic label, or empty when the
/// roster no longer holds them.
String wizardResultMemberName(
  MembershipWizardState state,
  MemberMembershipsStartResultItem item,
) =>
    _memberName(state, item.memberId);

String _memberName(MembershipWizardState state, String memberId) {
  for (final person in state.people) {
    if (person.memberId == memberId) return person.name;
  }
  return '';
}

/// The plan's name, read off the draft that ordered it and falling back to the
/// gym's catalogue for a row whose draft has since been edited away.
String _planName(MembershipWizardState state, String planId) {
  for (final person in state.people) {
    for (final draft in state.draftsFor(person.memberId)) {
      if (draft.plan.planId == planId) return draft.plan.planName;
    }
  }
  for (final plan in state.plans) {
    if (plan.planId == planId) return plan.planName;
  }
  return '';
}
