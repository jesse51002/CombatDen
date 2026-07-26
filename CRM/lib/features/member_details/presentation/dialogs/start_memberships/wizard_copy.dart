/// Every word the desk wizard says that the KIOSK has no version of.
///
/// The step heads and everything a shared component renders come from
/// `StaffFlowCopy`, because those words exist twice and a change to one is a
/// change to both. These do not: a payer switch, a one-off card, a discount, a
/// blocked plan reason with a control named in it — none of them can happen on
/// a lobby iPad, so there is no second voice for them to drift from. Plain
/// constants for the same reason `FlowDiscountCopy` is: they render once.
///
/// The voice is `StaffFlowCopy`'s — third person, addressed to somebody
/// selling on a member's behalf, and every destructive line states its
/// CONSEQUENCE rather than its mechanism.
library;

/// What the dialog is, and where it was opened from.
abstract final class WizardChromeCopy {
  static const String dialogTitle = 'Start memberships';
  static const String closeSemantic = 'Close without starting anything';

  /// The topbar's context line. It names the RECORD the run was opened from,
  /// which the rest of the flow never repeats — the payer can be somebody
  /// else entirely by the second screen.
  static String openedFrom(String memberName) =>
      '· opened from $memberName\'s profile';

  static String openedFromAt(String memberName, String gymName) =>
      '${openedFrom(memberName)} · $gymName';

  /// The plain-language run counter, over the REAL spine.
  static String stepOf(int step, int total) => 'Step $step of $total';

  /// The escape on step ONE. The surface's own escape word is `Start over`,
  /// which is a lie on the first screen — there is nothing yet to start over
  /// FROM, and the control leaves the run entirely.
  static const String cancelRun = 'Cancel';
}

/// The `who` step.
abstract final class WizardWhoCopy {
  static const String payingEyebrow = 'WHO\'S PAYING';
  static const String addEyebrow = 'ADD SOMEONE';

  static String paysForEveryone(String name) =>
      '$name pays for everyone above';

  /// Said BEFORE the control is used, because the switch cannot be undone.
  static const String payerSwitchWarning =
      'One card, one invoice. Changing the payer starts the run over — '
      'plans picked so far are cleared.';

  static const String changePayer = 'Change who\'s paying';

  static const String addNewTitle = 'Add someone new';
  static String addNewBody(String payerName) =>
      'Creates their profile, then authorizes $payerName to pay for them.';

  static const String findExistingTitle = 'Find an existing member';
  static String findExistingBody(String payerName) =>
      'Search the roster, then authorize $payerName to pay for them.';

  static const String ownEmailNote =
      'Everyone needs their own email — it\'s how they sign in.';

  /// The untick's consequence, on the row that performs it.
  static String untickNote(String firstName) =>
      'Untick to keep $firstName as the payer only. Anything picked for '
      'them is dropped.';

  // ── What a destructive control ACTUALLY dropped ─────────────────────────
  // Said AFTER the fact, from the cubit's own `MembershipWizardConsequence`.
  // The row's `untickNote` warns BEFORE; these three state what went, because
  // the old wizard's silent drop is what this whole type exists to end.

  static String untickedDrop({
    required String firstName,
    required int memberships,
  }) =>
      memberships == 0
          ? '$firstName is no longer getting a membership in this run.'
          : '$firstName is no longer getting a membership — '
              '${_picked(memberships)} dropped with them.';

  static String payerSwitchDrop({
    required String payerName,
    required int memberships,
    required int people,
  }) =>
      '$payerName pays for this run now. The roster was rebuilt, and '
      '${_picked(memberships)} for ${_people(people)} dropped with it.';

  static String membershipRemovedDrop({
    required String firstName,
    required int memberships,
    required int people,
  }) =>
      people == 0
          ? 'Took ${_picked(memberships)} off $firstName\'s lineup.'
          : 'Took ${_picked(memberships)} off $firstName\'s lineup — it was '
              'their last, so they are no longer getting a membership in '
              'this run.';

  static String _picked(int count) =>
      count == 1 ? 'one picked membership' : '$count picked memberships';

  static String _people(int count) =>
      count == 1 ? 'one person' : '$count people';

  static String continueWith(int people) =>
      people == 1 ? 'Continue' : 'Continue with $people people';

  static const String needSomebody =
      'Tick at least one person to carry on.';

  /// The people read failed. The old wizard swallowed this exception and left
  /// a spinner nobody could clear.
  static String loadFailedTitle(String payerName) =>
      'Couldn\'t load the people $payerName pays for';
  static const String loadFailedBody =
      'The connection dropped part-way. Nothing has been lost — the payer is '
      'unchanged and nothing has been charged.';
  static const String loadFailedFoot =
      'The list has to load before anyone can be picked.';
}

/// The `plans` step.
abstract final class WizardPlansCopy {
  static const String alreadyHasEyebrow = 'ALREADY HAS';
  static const String availableEyebrow = 'AVAILABLE PLANS';
  static const String pickingForEyebrow = 'PICKING FOR';
  static const String pickingForPayerEyebrow = 'PICKING FOR · THE PAYER';
  static const String payingForAllEyebrow = 'PAYING FOR ALL';

  static const String packsLabel = 'Packs';
  static const String fewerPacks = 'One fewer pack';
  static const String morePacks = 'One more pack';
  static const String packsNote =
      'The allowance and the price both follow the count.';

  /// The honesty line under a live price: the desk sells on it, and the
  /// Review's server figure is the one that is charged.
  static const String estimateNote =
      'Prices here are estimates. Review confirms the exact charge from the '
      'billing service.';

  /// Why a card is closed, and what clears it — the control, not the rule.
  static String blockedNote(String firstName, String planName) =>
      '$firstName is already on $planName — cancel or change it from their '
      'profile to sell it again. A repeat trial and a second, different '
      'recurring plan are both allowed.';

  static const String unpricedNote =
      'Plans with no active price aren\'t listed.';

  static String skipPerson(String firstName) => 'Skip $firstName';

  static String needAPlan(String firstName) =>
      'Pick at least one plan for $firstName, or skip them to leave them out '
      'of this run.';

  static String removeMembership(String planName, String firstName) =>
      'Remove $planName from $firstName\'s picks';

  static const String noPlansTitle =
      'This gym has no purchasable plans yet';
  static const String noPlansBody =
      'A plan needs an active price before it can be sold. Add one under '
      'Memberships → Plans, then come back to this run.';
  static const String noPlansFoot =
      'Nothing can be sold until this gym has at least one priced plan.';
  static const String plansFailedTitle = 'Couldn\'t load the plans';
  static const String plansFailedBody =
      'Nothing has been lost — the roster is intact and nothing has been '
      'charged.';
  static const String plansFailedFoot =
      'The catalogue has to load before a plan can be picked.';

  /// Everybody's last pick was taken back off, so the run has nobody left to
  /// price. Reachable from this step's own trash control, so it states the
  /// fact and names the way back rather than rendering an empty stage.
  static const String nobodyTitle = 'Nobody is getting a membership yet';
  static const String nobodyBody =
      'Every pick has been taken back off. Go back to the roster to tick '
      'somebody in, or start over.';
  static const String nobodyFoot =
      'Tick somebody in on the roster before plans can be picked.';
}

/// The `waivers` step.
abstract final class WizardWaiversCopy {
  static const String runEyebrow = 'WAIVERS IN THIS RUN';
  static const String signingForEyebrow = 'SIGNING FOR';
  static const String signedPill = 'Signed';
  static const String signingNowPill = 'Signing now';
  static const String nextPill = 'Next';
  static const String signAction = 'Sign and continue';
  static const String gate =
      'Every waiver listed has to be signed before this run can be priced.';

  /// A republished waiver announces itself rather than swapping the text
  /// under somebody mid-signature.
  static const String staleNotice =
      'This gym republished the waiver while it was open. The current '
      'version is on screen now — read it again before signing.';

  static String forMember(String name) => 'For $name';
  static String versionLabel(int version) => 'Version $version';

  /// A queued waiver whose name is not known yet — the queue is built from
  /// plan ids and only a server gate names a document. The row still prints:
  /// somebody still owes that signature.
  static const String unnamedWaiver = 'Waiver';
}

/// The `reviewCharges` step.
abstract final class WizardReviewCopy {
  static const String billedToEyebrow = 'BILLED TO';
  static const String firstPeriodEyebrow = 'THE FIRST PERIOD';
  static const String prorateNow = 'Prorate now';
  static const String noChargeNow = 'No charge now';

  static const String removalNote =
      'Removing the last membership from someone leaves them on the roster, '
      'unticked — nobody disappears from this list without saying so.';

  static String alreadyPaying(String name) =>
      'Already paying · $name\'s own memberships';
  static String monthlyTotal(String firstName) =>
      '$firstName\'s total each cycle';

  static const String addedByRun = 'What this run adds to the recurring bill.';

  static String primary(String amountLabel) => 'Review payment · $amountLabel';

  /// The same button before the billing service has named a figure. The
  /// amount is DROPPED rather than defaulted: a `$0.00` printed over a price
  /// nobody could work out is a number staff would read back to the payer.
  static const String primaryUnpriced = 'Review payment';

  /// A picked membership's rule line — what it gets you, and how many were
  /// bought. The count rides the same line because the allowance already
  /// follows it.
  static String lineRule(String allowance, int count) =>
      '$allowance · × $count';

  /// "Ella · Unlimited Monthly" — one person's one membership, on a money
  /// line or a receipt row. Shared with the payment echo and the results
  /// receipt so the same membership is named identically on all three.
  static String personPlan(String name, String planName) =>
      '$name · $planName';

  static const String nothingLeft =
      'Nothing left to start — pick a plan for someone, or start over.';

  static const String chargesFailedTitle = 'Couldn\'t work out the charges';
  static const String chargesFailedBody =
      'The billing service didn\'t answer. Nothing has been charged and '
      'nothing is lost — the lineup on the left is intact.';
  static const String chargesFailedFoot =
      'The charges have to load before payment can be taken.';
  static const String nothingToCharge =
      'Nothing to charge — these all start today at no cost.';
}

/// The `payment` step.
abstract final class WizardPaymentCopy {
  static const String cardOnFileEyebrow = 'CARD ON FILE';
  static const String oneOffEyebrow = 'ONE-OFF CARD';
  static const String whatPayWillDoEyebrow = 'WHAT PAY WILL DO';

  /// The group that REPLACES both card groups when this gym's Stripe account
  /// cannot take a card. One eyebrow, because there is one thing to say.
  static const String cardEyebrow = 'CARD';

  /// The step's own answering line. It names the amount and states plainly
  /// that nothing has moved yet — this is the last screen before it does.
  static String settlesToday(String amountLabel) =>
      'Nothing has been charged yet. $amountLabel settles today.';

  static const String cashLabel = 'Mark this as paid in cash';
  static String cashNote(String firstName) =>
      'Nothing goes through Stripe today and the memberships start straight '
      'away. Recurring memberships still bill $firstName\'s card on file '
      'from their next cycle — cash settles today only.';

  static String savedCardLabel(String firstName) =>
      'Charge $firstName\'s saved card';
  static const String savedCardNote =
      'Also the card every recurring membership in this run bills to.';
  static const String updateCard = 'Update card';

  /// The saved card's expiry, beside its chip. Staff about to charge a card
  /// need to know it has not run out; the chip itself carries only which card
  /// it is, because that is all a member ever needs.
  static String cardExpiry(int month, int year) {
    final mm = month.toString().padLeft(2, '0');
    final yy = (year % 100).toString().padLeft(2, '0');
    return 'exp $mm / $yy';
  }
  static String updateCardWarning(String firstName) =>
      'Updating this card re-bills EVERY recurring membership $firstName '
      'already pays for, not just today\'s. Cards can\'t be removed from '
      'here — do that on their profile.';
  static String noSavedCard(String firstName) =>
      '$firstName has no saved card yet — add one or settle in cash.';

  static const String useOneOffCard = 'Use a one-off card';
  static const String changeCard = 'Change';
  static const String removeCard = 'Remove';
  static const String notUsableTag = 'Not usable for this run';
  static const String oneOffNote =
      'Tokenized on this gym\'s Stripe account, never saved to a profile, '
      'never made the default.';

  // ── Why the one-off card cannot pay ─────────────────────────────────────
  // One sentence per `OneOffCardBlock`, each naming the CAUSE, what pays
  // instead, and BOTH ways out. The old wizard simply ignored the card here:
  // staff saw a card they had typed in and a charge that never touched it.

  static const String oneOffBlockedByCash =
      'Paid in cash is ticked, so nothing goes on any card today. Untick it '
      'to settle on this card, or remove the card.';
  static const String oneOffBlockedByRecurring =
      'A one-off card can only settle a run with no recurring membership in '
      'it, and this one has one — today goes on the card on file instead. '
      'Drop the recurring membership to use this card, or remove the card.';
  static const String oneOffBlockedByNoOneTime =
      'Nothing in this run bills once, so there is no one-time invoice for a '
      'one-off card to pay. Add a pack or a trial to use this card, or '
      'remove the card.';

  static const String cardEntryTitle = 'Card entry is unavailable right now';
  static const String cardEntryBody =
      'This gym\'s Stripe account hasn\'t finished onboarding, so cards '
      'can\'t be taken on this device. Settle in cash today, or finish setup '
      'and come back.';

  static const String needSettlement =
      'Tick paid in cash, or add a card, to carry on.';

  /// The same gate with card entry down — pointing at the one route that is
  /// actually open rather than at a card nobody can enter.
  static const String cashOnly =
      'Card entry is down — tick paid in cash to carry on, or fix card entry '
      'first.';

  static String pay(String amountLabel) => 'Pay $amountLabel';

  static String dueTodayOn(String? last4) => last4 == null || last4.isEmpty
      ? 'Due today'
      : 'Due today, on the card ending $last4';
  static const String addedEachCycle = 'Added each cycle by this run';
}

/// The `results` step.
abstract final class WizardResultsCopy {
  static const String startedEyebrow = 'STARTED TODAY';
  static const String processingTitle = 'Starting memberships…';
  static String processingBody(int count, String payerName) =>
      '${count == 1 ? 'One membership' : '$count memberships'} on '
      '$payerName\'s card. Leave this open — the next screen shows exactly '
      'what went through, one line per membership.';

  static const String openProfile = 'Tap any row to open that member\'s '
      'profile.';
  static const String retry = 'Retry the failed memberships';
  static const String partialNote =
      'The rows marked Started are paid for. Retrying only charges for the '
      'ones that didn\'t go through. Or tap Done and finish the rest from the '
      'payer\'s profile.';

  static String openMemberSemantic(String name) => 'Open $name\'s profile';

  static const String rejectedTitle = 'The request was not accepted';
  static const String rejectedSubtitle =
      'Nothing was created and nothing was charged.';
  static const String backToPayment = 'Back to payment';

  /// The four commit outcomes that produce no per-item breakdown at all.
  static const String unconfirmedTitle = 'This attempt was already sent';
  static const String unconfirmedBody =
      'It went out once and we never heard back, so it will not be sent '
      'again — that is the one thing that could charge twice. Check this '
      'payer in Stripe before retrying.';
  static const String alreadyStartedTitle = 'This run already went through';
  static const String alreadyStartedBody =
      'The billing service recognised it and replayed the original start. '
      'Nothing was charged twice.';
  static const String nothingToSendTitle = 'There was nothing left to send';
  static const String nothingToSendBody =
      'Every membership in this run has already been dealt with. Nothing '
      'left this device.';
  static const String failedTitle = 'The start could not be completed';
  static const String failedBody =
      'Nothing was created and nothing was charged. Go back to payment and '
      'try again.';
}
