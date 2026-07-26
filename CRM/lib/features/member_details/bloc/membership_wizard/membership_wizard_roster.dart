/// The `who` step's roster, and what its controls COST.
///
/// The roster is derived from the payer: who may be covered depends on who
/// pays (the backend's own self-or-authorized-payer rule), so there is exactly
/// one list and it is rebuilt, never patched. The consequence functions below
/// are the other half — every control here can destroy picked work, and the
/// old wizard did all three silently.
library;

import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_consequence.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_draft.dart';
import 'package:crm/features/member_details/bloc/membership_wizard/membership_wizard_person.dart';
import 'package:crm/features/member_details/data/models/member_detail_response.dart';

/// The people this run may charge for, payer first then the people they are
/// authorized to pay for, in the backend's own order.
///
/// Everybody the payer COULD cover is listed; [trainingMemberIds] decides who
/// is actually being sold something. That is deliberate — a roster that hid
/// the unticked rows would make "add somebody" the only way back to a person
/// staff had just unticked by mistake.
///
/// The address comes from [memberDetails] where the read has landed, because
/// the authorization row carries only a name: this is the desk's own screen
/// looking at the desk's own records, and staff correcting a typo need the
/// whole address (`IdentityPolicy.full`).
List<MembershipWizardPerson> rosterFor({
  required MembershipWizardPerson payer,
  required MemberDetailResponse? payerDetail,
  required Set<String> trainingMemberIds,
  Map<String, MemberDetailResponse> memberDetails = const {},
}) {
  String? emailOf(String memberId, String? fallback) =>
      memberDetails[memberId]?.personalInfo.email ?? fallback;

  return <MembershipWizardPerson>[
    MembershipWizardPerson(
      memberId: payer.memberId,
      name: payer.name,
      email: emailOf(payer.memberId, payer.email),
      photoUrl: payer.photoUrl,
      isPayer: true,
      training: trainingMemberIds.contains(payer.memberId),
    ),
    if (payerDetail != null)
      for (final account in payerDetail.authorizedToPayFor)
        if (account.memberId != payer.memberId)
          MembershipWizardPerson(
            memberId: account.memberId,
            name: account.fullName,
            email: emailOf(account.memberId, null),
            photoUrl: account.photoUrl,
            training: trainingMemberIds.contains(account.memberId),
          ),
  ];
}

/// How many memberships are picked across the whole run.
int totalPicked(Map<String, List<MembershipWizardDraft>> drafts) {
  var count = 0;
  for (final list in drafts.values) {
    count += list.length;
  }
  return count;
}

/// What switching the payer to [toMemberId] would cost.
///
/// Everything: the roster is rebuilt under the new payer and every pick in the
/// run dies with it, because a membership picked for somebody the new payer
/// cannot cover is not a membership anybody can buy. Only the LAUNCH member
/// survives the rebuild ticked — they are a valid participant for any chosen
/// payer — so everybody else in the cart is a person leaving the run.
MembershipWizardConsequence payerSwitchConsequence({
  required String toMemberId,
  required String toMemberName,
  required String launchMemberId,
  required List<MembershipWizardPerson> people,
  required Map<String, List<MembershipWizardDraft>> drafts,
}) {
  final leaving = people
      .where((p) => p.training && p.memberId != launchMemberId)
      .length;
  return MembershipWizardConsequence(
    kind: MembershipWizardConsequenceKind.payerSwitch,
    memberId: toMemberId,
    memberName: toMemberName,
    membershipsDropped: totalPicked(drafts),
    peopleDropped: leaving,
  );
}

/// What unticking [memberId] would cost — their whole lineup, and with it
/// their place in the cart.
///
/// Unticking somebody who has picked NOTHING costs nothing: they leave the
/// cart, which is the visible thing the control does, not a hidden loss. It is
/// counted as a dropped person only when work dies with them, so a warning is
/// never printed beside a control with nothing to warn about.
MembershipWizardConsequence untickConsequence({
  required MembershipWizardPerson person,
  required Map<String, List<MembershipWizardDraft>> drafts,
}) {
  final picked = drafts[person.memberId]?.length ?? 0;
  return MembershipWizardConsequence(
    kind: MembershipWizardConsequenceKind.untickPerson,
    memberId: person.memberId,
    memberName: person.name,
    membershipsDropped: picked,
    peopleDropped: picked > 0 ? 1 : 0,
  );
}

/// What removing ONE membership would cost — itself, plus the person when it
/// was their last.
MembershipWizardConsequence removeMembershipConsequence({
  required MembershipWizardPerson person,
  required String planId,
  required Map<String, List<MembershipWizardDraft>> drafts,
}) {
  final list = drafts[person.memberId] ?? const <MembershipWizardDraft>[];
  final held = list.any((d) => d.plan.planId == planId);
  final wasLast = held && list.length == 1;
  return MembershipWizardConsequence(
    kind: MembershipWizardConsequenceKind.removeMembership,
    memberId: person.memberId,
    memberName: person.name,
    membershipsDropped: held ? 1 : 0,
    peopleDropped: wasLast ? 1 : 0,
  );
}

/// [drafts] with [memberId]'s lineup dropped entirely.
Map<String, List<MembershipWizardDraft>> draftsWithout(
  Map<String, List<MembershipWizardDraft>> drafts,
  String memberId,
) =>
    {
      for (final entry in drafts.entries)
        if (entry.key != memberId) entry.key: entry.value,
    };

/// [drafts] with one membership taken off [memberId]'s lineup; the whole entry
/// disappears when it was their last, so an empty list can never masquerade as
/// a configured person.
Map<String, List<MembershipWizardDraft>> draftsWithMembershipRemoved(
  Map<String, List<MembershipWizardDraft>> drafts,
  String memberId,
  String planId,
) {
  final remaining = [
    for (final draft in drafts[memberId] ?? const <MembershipWizardDraft>[])
      if (draft.plan.planId != planId) draft,
  ];
  if (remaining.isEmpty) return draftsWithout(drafts, memberId);
  return {...drafts, memberId: remaining};
}
