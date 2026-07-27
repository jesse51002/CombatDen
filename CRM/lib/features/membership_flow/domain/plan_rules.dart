/// The ONE rulebook deciding which plans a person may be sold — shared by the
/// self-serve kiosk grid and the staff start-memberships wizard.
///
/// Two kinds of rule live here as DELIBERATELY different types: a [PlanGate]
/// closes a plan, a [PlanNote] only annotates one. Separate types mean an
/// advisory can never quietly become a block — the compiler keeps them apart.
///
/// Every gate takes the FACTS it needs, never a surface's state object, so the
/// kiosk (carrying a precomputed held-plan list per roster person) and the
/// wizard (holding the member's raw membership rows) run one implementation.
library;

import 'package:crm/features/member_details/data/models/membership_info.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/member_details/data/models/plan_type.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';

/// Plan-type values used by the backend `plan_type` on a membership row
/// ([MembershipInfo.planType] is the raw string; a catalogue plan carries the
/// parsed [PlanType] instead).
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
///
/// Both clients now derive it from THIS constant rather than from two
/// hand-matched copies, so "the two agree" is a fact about the import graph.
const _blockingStatuses = {
  MembershipStatus.active,
  MembershipStatus.frozen,
  MembershipStatus.overdue,
};

/// Statuses a membership is finished in — a trial that has run its course.
const _finishedStatuses = {
  MembershipStatus.cancelled,
  MembershipStatus.ended,
};

/// A rule that CLOSES a plan to one person. Sealed so a surface switching on
/// which gate fired cannot ship without handling a newly-added one.
sealed class PlanGate {
  const PlanGate();

  /// Whether this gate closes [plan] to the person it was built for.
  bool blocks(MembershipPlanResponse plan);

  /// The words a surface renders when this gate closes a plan.
  String get reason;
}

/// The person already holds this RECURRING plan, **mirroring the backend's own
/// duplicate guard** rather than a wider house rule:
/// `member_memberships_check_existing.sql` rejects a start only for
/// `plan_type = 'recurring'` at `status IN ('active', 'frozen')`, keyed on
/// `plan_id`. So the block is recurring-only and per plan, over
/// [_blockingStatuses] (that status list in the client's wider display enum —
/// read its doc before touching it).
///
/// Every other combination is a sale the backend takes, so both surfaces must
/// offer it: `one_time` and `trial` packs may STACK (another pack before the
/// first is used up, or a repeat trial — exactly what staff grant at a desk),
/// and a member on one recurring plan may still be sold a DIFFERENT one.
final class RecurringHeldGate extends PlanGate {
  /// The recurring plan ids the person holds in a blocking state.
  final Set<String> heldPlanIds;

  const RecurringHeldGate(this.heldPlanIds);

  /// The gate derived from a participant's own membership rows.
  factory RecurringHeldGate.fromMemberships(
    List<MembershipInfo> memberships,
  ) =>
      RecurringHeldGate({
        for (final m in memberships)
          if (m.planType == _recurring &&
              _blockingStatuses.contains(m.status))
            m.planId,
      });

  @override
  bool blocks(MembershipPlanResponse plan) =>
      plan.planType == PlanType.recurring &&
      heldPlanIds.contains(plan.planId);

  @override
  String get reason => 'Already on this plan';
}

/// Trials are one to a member: any prior trial closes EVERY trial plan, so its
/// words never name one. A KIOSK-only gate — staff may still grant a repeat
/// trial at the desk, where they get [PastTrialNote] instead.
final class TrialOnceGate extends PlanGate {
  /// Whether this person has ever held a trial here, whatever its state.
  final bool hadTrial;

  const TrialOnceGate({required this.hadTrial});

  /// The gate derived from a participant's own membership rows. Every row ever
  /// held counts — a trial finished a year ago still closes the plan.
  factory TrialOnceGate.fromMemberships(List<MembershipInfo> memberships) =>
      TrialOnceGate(
        hadTrial: memberships.any((m) => m.planType == _trial),
      );

  @override
  bool blocks(MembershipPlanResponse plan) =>
      hadTrial && plan.planType == PlanType.trial;

  @override
  String get reason => 'Trial already used';
}

/// A rule that only ADVISES about a plan. A note never closes a card; it is
/// its own type precisely so it cannot become one.
sealed class PlanNote {
  const PlanNote();

  /// Whether this note applies to [plan].
  bool applies(MembershipPlanResponse plan);

  /// The words a surface renders alongside the plan.
  String get note;
}

/// The person completed this trial in the past. Still selectable — granting a
/// repeat trial is exactly what staff do at a desk.
final class PastTrialNote extends PlanNote {
  /// The trial plan ids the person has finished.
  final Set<String> planIds;

  const PastTrialNote(this.planIds);

  factory PastTrialNote.fromMemberships(List<MembershipInfo> memberships) =>
      PastTrialNote({
        for (final m in memberships)
          if (m.planType == _trial && _finishedStatuses.contains(m.status))
            m.planId,
      });

  @override
  bool applies(MembershipPlanResponse plan) => planIds.contains(plan.planId);

  @override
  String get note => 'Had this trial in the past';
}

/// The first gate in [gates] that closes [plan], or null when it is open.
/// Order is the caller's: the first match wins, so a surface controls which
/// explanation a doubly-blocked plan gets.
PlanGate? firstBlockingGate(
  List<PlanGate> gates,
  MembershipPlanResponse plan,
) {
  for (final gate in gates) {
    if (gate.blocks(plan)) return gate;
  }
  return null;
}

/// planId → the blocking reason's words, for a surface that renders a per-plan
/// map rather than testing catalogue plans one at a time. Only
/// [RecurringHeldGate] can be expressed this way — [TrialOnceGate] closes
/// every trial plan and names none.
Map<String, String> disabledPlanReasons(
  List<MembershipInfo> participantMemberships,
) {
  final gate = RecurringHeldGate.fromMemberships(participantMemberships);
  return {for (final id in gate.heldPlanIds) id: gate.reason};
}

/// planId → soft note for trials the participant has completed before
/// (cancelled/ended). Still selectable.
Map<String, String> warningPlanReasons(
  List<MembershipInfo> participantMemberships,
) {
  final note = PastTrialNote.fromMemberships(participantMemberships);
  return {for (final id in note.planIds) id: note.note};
}
