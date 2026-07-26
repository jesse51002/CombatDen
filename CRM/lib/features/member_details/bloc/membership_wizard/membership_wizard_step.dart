/// The staff start-memberships flow's step spine — `5 + N`, where N is the
/// number of people getting a membership in this run.
///
/// It is a LIST computed from the run rather than a fixed ladder, because two
/// of its entries are counted rather than declared: the plans step is walked
/// once per training person, and the waivers step exists only when somebody
/// still owes a signature. A surface asks for the list and its own position in
/// it; nothing here knows what a rail looks like.
library;

/// One screen of the staff flow.
///
/// `who` merges what used to be two steps (choose the payer, then tick who
/// joins) — the payer pill and the "getting a membership" check are two
/// controls on ONE roster, so splitting them made staff answer half a question
/// twice. `reviewCharges` likewise merges the old review and preview steps:
/// the proration choice belongs where its consequence is visible.
enum MembershipWizardStep {
  /// The roster: who pays, and who is getting a membership.
  who,

  /// One training person's plans (and their inline discounts).
  plans,

  /// The signatures the picked plans require, derived PROACTIVELY — before
  /// the money, not after a 422.
  waivers,

  /// What is being bought and what it costs today, with the proration choice.
  reviewCharges,

  /// Cash, the saved card, or a one-off card. PAY fires here.
  payment,

  /// The per-membership created/failed breakdown.
  results,
}

/// The steps this run actually walks, in order.
///
/// [trainingPeople] is N. A run with nobody training still yields one plans
/// entry, so the spine never collapses to something the footer cannot count
/// against while staff are still assembling the roster.
List<MembershipWizardStep> membershipWizardSteps({
  required int trainingPeople,
  required bool hasWaivers,
}) {
  final people = trainingPeople < 1 ? 1 : trainingPeople;
  return <MembershipWizardStep>[
    MembershipWizardStep.who,
    for (var i = 0; i < people; i++) MembershipWizardStep.plans,
    if (hasWaivers) MembershipWizardStep.waivers,
    MembershipWizardStep.reviewCharges,
    MembershipWizardStep.payment,
    MembershipWizardStep.results,
  ];
}

/// Where [step] sits in the spine — the plans step resolved by [personIndex],
/// since N of them share one enum value.
int membershipWizardStepIndex({
  required MembershipWizardStep step,
  required int personIndex,
  required int trainingPeople,
  required bool hasWaivers,
}) {
  final people = trainingPeople < 1 ? 1 : trainingPeople;
  final atPlansEnd = 1 + people;
  final waiverSlot = hasWaivers ? 1 : 0;
  return switch (step) {
    MembershipWizardStep.who => 0,
    MembershipWizardStep.plans =>
      1 + (personIndex < 0 ? 0 : (personIndex >= people ? people - 1 : personIndex)),
    MembershipWizardStep.waivers => atPlansEnd,
    MembershipWizardStep.reviewCharges => atPlansEnd + waiverSlot,
    MembershipWizardStep.payment => atPlansEnd + waiverSlot + 1,
    MembershipWizardStep.results => atPlansEnd + waiverSlot + 2,
  };
}
