import 'package:crm/features/member_details/data/models/member_detail_response.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_item.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_payment.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_request.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_result_item.dart';
import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/member_details/data/models/proration_behavior.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_membership/start_membership_participant.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/membership_draft.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_plan_rules.dart'
    as rules;

/// Pure derivations the wizard orchestrator feeds the step
/// body — selection ordering, per-member rule inputs, and
/// the wire request assembly. Kept as a free-function
/// module (no instance state), like `start_plan_rules.dart`.

/// Selected members in stable family order (payer first).
List<StartMembershipParticipant> configMembersFor({
  required StartMembershipParticipant payer,
  required MemberDetailResponse? payerDetail,
  required Set<String> selectedMemberIds,
}) {
  final all = <StartMembershipParticipant>[
    payer,
    if (payerDetail != null)
      ...payerDetail.linkedAccounts.map(
        (a) => StartMembershipParticipant(
          memberId: a.memberId,
          name: a.fullName,
          photoUrl: a.photoUrl,
          isPayer: false,
        ),
      ),
  ];
  return all
      .where(
        (p) => selectedMemberIds.contains(p.memberId),
      )
      .toList();
}

/// The member at [memberIndex], clamped into [members].
StartMembershipParticipant? currentMemberOf(
  List<StartMembershipParticipant> members,
  int memberIndex,
) {
  if (members.isEmpty) return null;
  final i = memberIndex < members.length
      ? memberIndex
      : members.length - 1;
  return members[i];
}

/// planId → disabled reason for [member], from their
/// best-effort detail in [memberDetails] (empty when the
/// fetch failed — the backend still rejects duplicates).
Map<String, String> disabledPlanReasonsFor(
  StartMembershipParticipant? member,
  Map<String, MemberDetailResponse> memberDetails,
) {
  final detail = memberDetails[member?.memberId];
  if (member == null || detail == null) return const {};
  return rules.disabledPlanReasons(
    rules.membershipsForParticipant(
      detail.memberships,
      member.memberId,
    ),
  );
}

/// The member's existing non-terminal memberships — the
/// Plans step's "Already has" block. Same best-effort
/// detail fetch as the plan rules: empty when the fetch
/// failed.
List<MembershipInfo> existingMembershipsFor(
  StartMembershipParticipant? member,
  Map<String, MemberDetailResponse> memberDetails,
) {
  final detail = memberDetails[member?.memberId];
  if (member == null || detail == null) return const [];
  return rules.currentMembershipsForParticipant(
    detail.memberships,
    member.memberId,
  );
}

/// Whether any configured draft is a recurring plan.
bool hasRecurringDrafts(
  List<StartMembershipParticipant> members,
  Map<String, List<MembershipDraft>> drafts,
) =>
    members.any(
      (m) => (drafts[m.memberId] ?? const []).any(
        (d) => d.plan.planType == PlanType.recurring,
      ),
    );

/// Whether any configured draft is a one-time / trial plan
/// (non-recurring) — gates the one-off-card option.
bool hasOneTimeDrafts(
  List<StartMembershipParticipant> members,
  Map<String, List<MembershipDraft>> drafts,
) =>
    members.any(
      (m) => (drafts[m.memberId] ?? const []).any(
        (d) => d.plan.planType != PlanType.recurring,
      ),
    );

Map<String, String> memberNamesOf(
  List<StartMembershipParticipant> members,
) =>
    {for (final m in members) m.memberId: m.name};

Map<String, String> planNamesOf(
  Map<String, List<MembershipDraft>> drafts,
) =>
    {
      for (final list in drafts.values)
        for (final d in list)
          d.plan.planId: d.plan.planName,
    };

/// The one wire request for this run, or null when nothing
/// is configured yet.
MemberMembershipsStartRequest? buildStartRequest({
  required String idempotencyKey,
  required String payerMemberId,
  required String gymId,
  required ProrationBehavior prorationBehavior,
  required bool paidWithCash,
  required List<StartMembershipParticipant> configMembers,
  required Map<String, List<MembershipDraft>> drafts,
  MemberMembershipsStartPayment? payment,
}) {
  final items = <MemberMembershipsStartItem>[];
  for (final m in configMembers) {
    for (final d
        in drafts[m.memberId] ?? const <MembershipDraft>[]) {
      final item = d.toItem(m.memberId);
      if (item != null) items.add(item);
    }
  }
  if (items.isEmpty) return null;
  return MemberMembershipsStartRequest(
    payerMemberId: payerMemberId,
    gymId: gymId,
    idempotencyKey: idempotencyKey,
    prorationBehavior: prorationBehavior,
    paidWithCash: paidWithCash,
    payment: payment,
    memberships: items,
  );
}

/// The failed result items re-staged as fresh wire items —
/// the results step's "retry failed" input.
List<MemberMembershipsStartItem> retryItemsFor(
  List<MemberMembershipsStartResultItem> failed,
  Map<String, List<MembershipDraft>> drafts,
) {
  final items = <MemberMembershipsStartItem>[];
  for (final f in failed) {
    for (final d
        in drafts[f.memberId] ?? const <MembershipDraft>[]) {
      if (d.plan.planId != f.planId) continue;
      final item = d.toItem(f.memberId);
      if (item != null) items.add(item);
    }
  }
  return items;
}

/// [drafts] with [plan] toggled in or out.
List<MembershipDraft> draftsWithPlanToggled(
  List<MembershipDraft> drafts,
  MembershipPlanResponse plan,
) {
  final list = List<MembershipDraft>.from(drafts);
  final i = list.indexWhere(
    (d) => d.plan.planId == plan.planId,
  );
  if (i >= 0) {
    list.removeAt(i);
  } else {
    list.add(MembershipDraft(plan: plan));
  }
  return list;
}
