/// The ordered steps of the Start Memberships wizard.
///
/// [plans] and [discounts] repeat per selected member (pick
/// plans for member A, then A's discounts, then member B's
/// plans, …) before the flow converges on the shared
/// [review] → [preview] → [payment] → [results] tail.
/// Nothing mutates until PAY on the [payment] step;
/// [results] renders the per-membership created/failed
/// breakdown.
enum StartMembershipsStep {
  /// Who pays — the one top-level paying account.
  payer,

  /// Who's getting memberships — multi-select of the payer
  /// + members already linked to the payer.
  members,

  /// Per member: pick this member's plans.
  plans,

  /// Per member: discounts for each picked plan.
  discounts,

  /// Who's getting what — a pure-content summary (members →
  /// memberships → discounts, names only, no prices).
  review,

  /// Required-but-unsigned waivers for the selected members.
  /// Reached when the start POST returns a 422 waiver gate.
  signWaivers,

  /// The server-side charge preview (one-time / due now /
  /// recurring). Confirm = navigation only.
  preview,

  /// Card-on-file vs cash + the PAY trigger.
  payment,

  /// The per-membership created/failed breakdown.
  results,
}

/// The top-level groups the step indicator presents.
///
/// Pure presentation — navigation still walks
/// [StartMembershipsStep] one step at a time; the indicator
/// just rolls the wizard steps up into legible segments,
/// each carrying its substep progress.
///
/// [addMember] is a leading, always-completed segment shown ONLY when the
/// wizard is launched from the add-member flow (the create already happened
/// before the wizard mounts). No [StartMembershipsStep] maps to it — the
/// indicator renders it as done-chrome. Member-detail launches omit it, so
/// that context stays exactly three groups.
enum StartMembershipsStepGroup {
  /// Group 0 — add-member-flow only; always shown completed.
  addMember('Add member', 1),

  /// Group 1 — substep: payer.
  selectPayer('Select payer', 1),

  /// Group 2 — substeps: who / plans / deals / review / sign.
  selectMemberships('Select memberships', 5),

  /// Group 3 — substeps: preview / pay / done.
  confirmation('Confirmation', 3);

  /// The segment title shown in the indicator.
  final String title;

  /// How many wizard steps this group rolls up.
  final int substepCount;

  const StartMembershipsStepGroup(
    this.title,
    this.substepCount,
  );
}

/// Maps each wizard step to its indicator group and its
/// zero-based position within that group.
extension StartMembershipsStepGrouping
    on StartMembershipsStep {
  StartMembershipsStepGroup get group {
    switch (this) {
      case StartMembershipsStep.payer:
        return StartMembershipsStepGroup.selectPayer;
      case StartMembershipsStep.members:
      case StartMembershipsStep.plans:
      case StartMembershipsStep.discounts:
      case StartMembershipsStep.review:
      case StartMembershipsStep.signWaivers:
        return StartMembershipsStepGroup
            .selectMemberships;
      case StartMembershipsStep.preview:
      case StartMembershipsStep.payment:
      case StartMembershipsStep.results:
        return StartMembershipsStepGroup.confirmation;
    }
  }

  /// Zero-based position within [group].
  int get substepIndex {
    switch (this) {
      case StartMembershipsStep.payer:
      case StartMembershipsStep.members:
      case StartMembershipsStep.preview:
        return 0;
      case StartMembershipsStep.plans:
      case StartMembershipsStep.payment:
        return 1;
      case StartMembershipsStep.discounts:
      case StartMembershipsStep.results:
        return 2;
      case StartMembershipsStep.review:
        return 3;
      case StartMembershipsStep.signWaivers:
        return 4;
    }
  }
}
