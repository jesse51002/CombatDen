/// The ordered steps of the Start Memberships wizard.
///
/// [plans] and [discounts] repeat per selected member (pick
/// plans for member A, then A's discounts, then member B's
/// plans, …) before the flow converges on the shared
/// [preview] → [payment] → [results] tail. Nothing mutates
/// until PAY on the [payment] step; [results] renders the
/// per-membership created/failed breakdown.
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

  /// The server-side three-way preview (one-time / due now
  /// / recurring). Confirm = navigation only.
  preview,

  /// Card-on-file vs cash + the PAY trigger.
  payment,

  /// The per-membership created/failed breakdown.
  results,
}
