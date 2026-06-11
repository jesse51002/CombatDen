import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';

/// Pure helpers that derive the plan-step selection rules
/// from a participant's current memberships. Kept as a
/// free-function module (no instance state) so the
/// orchestrator and plan step share one source of truth.

/// One-time plan value used by the backend `plan_type`.
const _oneTime = 'one_time';
const _trial = 'trial';

/// Statuses that block re-enrolling in a recurring/trial
/// plan the participant already actively holds.
const _blockingStatuses = {
  MembershipStatus.active,
  MembershipStatus.trial,
  MembershipStatus.frozen,
  MembershipStatus.overdue,
};

/// Memberships from [all] that the participant [memberId]
/// is actually enrolled in. A paying parent's detail also
/// lists plans they cover for linked children, so filter to
/// rows whose `members` map includes the participant —
/// otherwise the parent would inherit a child's active plan
/// and get wrongly blocked.
List<MembershipInfo> membershipsForParticipant(
  List<MembershipInfo> all,
  String memberId,
) =>
    all
        .where((m) => m.members.containsKey(memberId))
        .toList();

/// The participant's own status on a membership — their
/// per-member roster status when present (a family plan's
/// covered members each carry their own), falling back to
/// the plan-level status.
MembershipStatus participantStatus(
  MembershipInfo membership,
  String memberId,
) =>
    membership.payingForMemberFor(memberId)?.status ??
    membership.status;

/// Memberships the participant currently holds in a
/// non-terminal state — the Plans step's "Already has"
/// block input. Attribution is per member: a membership
/// counts only when the participant is covered by it, and
/// terminality follows their own status on it.
List<MembershipInfo> currentMembershipsForParticipant(
  List<MembershipInfo> all,
  String memberId,
) =>
    membershipsForParticipant(all, memberId)
        .where(
          (m) => !const {
            MembershipStatus.cancelled,
            MembershipStatus.ended,
          }.contains(participantStatus(m, memberId)),
        )
        .toList();

/// planId → "already on this plan" for recurring/trial
/// plans the participant already actively holds. One-time
/// plans are excluded — repeat one-time purchases are
/// allowed.
Map<String, String> disabledPlanReasons(
  List<MembershipInfo> participantMemberships,
) {
  final blocking = participantMemberships.where(
    (m) =>
        m.planType != _oneTime &&
        _blockingStatuses.contains(m.status),
  );
  return {
    for (final m in blocking) m.planId: 'Already on this plan',
  };
}

/// True when the participant already has an active one-time
/// membership — surfaced as a soft note on one-time plan
/// tiles (not a block).
bool participantHasActiveOneTime(
  List<MembershipInfo> participantMemberships,
) =>
    participantMemberships.any(
      (m) =>
          m.planType == _oneTime &&
          const {
            MembershipStatus.active,
            MembershipStatus.frozen,
            MembershipStatus.overdue,
          }.contains(m.status),
    );

/// planId → soft note for trials the participant has
/// completed before (cancelled/ended). Still selectable.
Map<String, String> warningPlanReasons(
  List<MembershipInfo> participantMemberships,
) {
  final pastTrials = participantMemberships.where(
    (m) =>
        m.planType == _trial &&
        const {
          MembershipStatus.cancelled,
          MembershipStatus.ended,
        }.contains(m.status),
  );
  return {
    for (final m in pastTrials)
      m.planId: 'Had this trial in the past',
  };
}
