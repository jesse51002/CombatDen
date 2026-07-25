import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';

/// Pure helpers that derive the plan-step selection rules
/// from a participant's current memberships. Kept as a
/// free-function module (no instance state) so the
/// orchestrator and plan step share one source of truth.

/// Plan-type values used by the backend `plan_type`.
const _oneTime = 'one_time';
const _trial = 'trial';
const _recurring = 'recurring';

/// Statuses that block re-enrolling in a RECURRING plan the
/// participant already holds. **This set IS the backend's
/// `status IN ('active', 'frozen')`, translated.**
///
/// The guard (`member_memberships_check_existing.sql`) reads
/// the `member_memberships_status` view, whose `CASE` emits
/// exactly four values — `cancelled` / `ended` / `frozen` /
/// `active` — and **never `overdue`**. A past-due membership is
/// plain `active` there. [MembershipStatus] is a wider CRM
/// DISPLAY enum that splits that one backend `active` in two:
/// the backend derives `overdue` for an `active` row whose
/// `next_due_date` has passed (`src/shared/membership_status.py`
/// + `sql/membership_overdue.sql`) and hands it to the client
/// as its own status.
///
/// So `{active, frozen, overdue}` on this side is what mirrors
/// `('active','frozen')` on that side — the set only looks
/// wider than the SQL because the client splits one backend
/// status into two. Matching the SQL string-for-string would
/// under-block: a member in arrears on a recurring plan would
/// be offered it again and eat a rejection at the money step.
///
/// `trial` is a display status too, but it belongs to trial
/// packs, and `plan_type = 'recurring'` already excludes those
/// — see [disabledPlanReasons]. The kiosk's
/// `heldRecurringPlanIds` derives the same rule, so the two
/// clients agree.
const _blockingStatuses = {
  MembershipStatus.active,
  MembershipStatus.frozen,
  MembershipStatus.overdue,
};

/// The participant's memberships. The member-detail fetch is
/// member-centric — already scoped to the viewed member — so every
/// row in [all] is theirs. Kept as a named helper (the identity) so
/// the orchestrator and plan step share one source of truth.
List<MembershipInfo> membershipsForParticipant(
  List<MembershipInfo> all,
  String memberId,
) =>
    all;

/// The participant's status on a membership — its flat status; each
/// card is the participant's own membership row.
MembershipStatus participantStatus(
  MembershipInfo membership,
  String memberId,
) =>
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

/// planId → "already on this plan", **mirroring the backend's
/// own duplicate guard** rather than a wider house rule:
/// `member_memberships_check_existing.sql` rejects a start only
/// for `plan_type = 'recurring'` at `status IN ('active',
/// 'frozen')`, keyed on `plan_id`. So the block is
/// recurring-only and per plan, over [_blockingStatuses] (which
/// is that status list expressed in the client's wider display
/// enum — read its doc before touching it).
///
/// Every other combination is a sale the backend takes, so the
/// wizard must offer it: `one_time` and `trial` packs are
/// allowed to STACK (a member may buy another pack before the
/// first is used up, or repeat a trial — a repeat trial is
/// exactly what staff grant at a desk), and a member already on
/// one recurring plan may still be sold a DIFFERENT one.
/// Refusing any of those was the CRM turning away money the
/// API would have accepted, with no override anywhere in the
/// wizard.
Map<String, String> disabledPlanReasons(
  List<MembershipInfo> participantMemberships,
) {
  final blocking = participantMemberships.where(
    (m) =>
        m.planType == _recurring &&
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
