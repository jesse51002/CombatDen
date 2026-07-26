/// Every word the payer switch says.
///
/// Desk-only — a member facing a lobby iPad can never change who pays — so
/// these are plain constants for the same reason `FlowDiscountCopy`'s are:
/// they render once, and there is no second voice for them to drift from.
///
/// The voice is `StaffFlowCopy`'s: third person, addressed to somebody selling
/// on a member's behalf, and every line states its CONSEQUENCE rather than its
/// mechanism.
library;

abstract final class ChangePayerCopy {
  static const String title = 'Change who\'s paying';

  /// Said BEFORE the switch is used, because it cannot be undone.
  static const String intro =
      'One card, one invoice. Switching the payer starts the run over — the '
      'roster is rebuilt around whoever pays, so plans picked so far are '
      'cleared.';

  // ── The three groups of people already on screen ─────────────────────────

  static const String selfEyebrow = 'SELF-PAY';
  static const String selfMeta =
      'Member getting a membership — pays for themselves';

  static const String authorizedEyebrow = 'ALREADY AUTHORIZED';
  static const String authorizedMeta = 'Authorized payer for this member';

  static const String inRunEyebrow = 'ALSO IN THIS RUN';

  /// What picking a roster member COSTS: one signature, taken first. The row
  /// is a jump rather than an answer, so it says where it jumps to.
  static String inRunMeta(String launchName) =>
      'On this run\'s roster. Picking them signs the agreement to pay for '
      '$launchName first.';

  // ── Somebody who is on neither list ──────────────────────────────────────

  static const String addEyebrow = 'SOMEONE NOT LISTED';

  static const String createTitle = 'Add someone new as the payer';
  static const String createBody =
      'Creates their profile, then authorizes them to pay for this member.';

  static const String linkTitle = 'Find an existing member';
  static const String linkBody =
      'Search the roster, then authorize them to pay for this member.';

  // ── Chrome ───────────────────────────────────────────────────────────────

  static const String confirm = 'Use this payer';
  static const String cancel = 'Cancel';
}
