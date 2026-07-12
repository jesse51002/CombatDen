import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_memberships_step.dart';

/// Plain-language title for one wizard step (finer-grained than the group
/// title shown in the indicator).
String startStepTitle(StartMembershipsStep step) {
  switch (step) {
    case StartMembershipsStep.payer:
      return 'Choose who pays';
    case StartMembershipsStep.members:
      return 'Choose who joins';
    case StartMembershipsStep.plans:
      return 'Pick plans';
    case StartMembershipsStep.discounts:
      return 'Apply discounts';
    case StartMembershipsStep.review:
      return 'Review';
    case StartMembershipsStep.signWaivers:
      return 'Sign waivers';
    case StartMembershipsStep.preview:
      return 'Preview charges';
    case StartMembershipsStep.payment:
      return 'Payment';
    case StartMembershipsStep.results:
      return 'Summary';
  }
}

/// Total number of linear wizard steps for a run of [memberCount] members
/// (each member contributes a plans + discounts pair). [hasWaiver] adds the
/// conditional sign-waivers step once the gate is hit. Excludes the
/// add-member step — see [addMemberFlowStepCount].
int wizardStepCount({
  required int memberCount,
  required bool hasWaiver,
}) =>
    // payer + members (2) + plans/discounts per member (2N) + review +
    // preview + payment + results (4), plus the conditional waiver step.
    6 + 2 * memberCount + (hasWaiver ? 1 : 0);

/// Total steps for the whole add-member flow (the leading create step plus
/// the wizard). Used for the "Step 1 of M" line on the create phase.
int addMemberFlowStepCount({
  required int memberCount,
  required bool hasWaiver,
}) =>
    1 + wizardStepCount(memberCount: memberCount, hasWaiver: hasWaiver);

/// The 1-based global position (n) and total (m) of a wizard [step].
///
/// [memberIndex] is the current member's 0-based index in the per-member
/// plans/discounts loop; [memberCount] the number of members in the run.
/// [showAddMemberGroup] shifts everything by one when the wizard runs inside
/// the add-member flow (the create step is step 1).
({int n, int m}) startStepPosition({
  required StartMembershipsStep step,
  required int memberIndex,
  required int memberCount,
  required bool hasWaiver,
  required bool showAddMemberGroup,
}) {
  final base = showAddMemberGroup ? 1 : 0;
  final m = base +
      wizardStepCount(memberCount: memberCount, hasWaiver: hasWaiver);
  final loopEnd = base + 2 + 2 * memberCount; // after the per-member loop
  final waiverBump = hasWaiver ? 1 : 0;
  final n = switch (step) {
    StartMembershipsStep.payer => base + 1,
    StartMembershipsStep.members => base + 2,
    StartMembershipsStep.plans => base + 2 + 2 * memberIndex + 1,
    StartMembershipsStep.discounts => base + 2 + 2 * memberIndex + 2,
    StartMembershipsStep.review => loopEnd + 1,
    StartMembershipsStep.signWaivers => loopEnd + 2,
    StartMembershipsStep.preview => loopEnd + waiverBump + 2,
    StartMembershipsStep.payment => loopEnd + waiverBump + 3,
    StartMembershipsStep.results => loopEnd + waiverBump + 4,
  };
  return (n: n, m: m);
}

/// The full `Title · Step N of M` line for a wizard [step].
String startStepLabel({
  required StartMembershipsStep step,
  required int memberIndex,
  required int memberCount,
  required bool hasWaiver,
  required bool showAddMemberGroup,
}) {
  final pos = startStepPosition(
    step: step,
    memberIndex: memberIndex,
    memberCount: memberCount,
    hasWaiver: hasWaiver,
    showAddMemberGroup: showAddMemberGroup,
  );
  return '${startStepTitle(step)} · Step ${pos.n} of ${pos.m}';
}
