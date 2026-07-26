import 'package:crm/features/member_details/data/models/member_memberships_start_status.dart';

/// Every user-facing WORD the shared component set renders.
///
/// One component set serves two surfaces that speak differently — the member
/// reads "I'm getting a membership" on the lobby iPad, staff read "Getting a
/// membership" at the desk — so the widgets carry no sentence of their own.
/// A component asks for the LINE it is rendering and the surface's own copy
/// decides the words, exactly as it asks the scale for a size.
///
/// **An abstract class with typed methods, never a map of strings.** A missing
/// entry has to fail at COMPILE time: a map would hand back null (or a silent
/// empty string) at whatever moment the second surface first reached that
/// screen, which is the wording drift this module exists to make impossible.
///
/// **Methods take the data they interpolate — never a pre-formatted sentence.**
/// A caller passing `'Signed today by Marcus'` has already made the wording
/// decision this interface exists to own; it passes `signerName` and the copy
/// assembles the line. That is also what lets one surface reorder or drop a
/// clause the other keeps.
///
/// `test/features/membership_flow/presentation_has_no_copy_test.dart` asserts
/// that no sentence-like literal survives under `presentation/`, so a wording
/// change cannot land on one surface only.
abstract class MembershipFlowCopy {
  const MembershipFlowCopy();

  // ── Actions ───────────────────────────────────────────────────────────────
  // The words on the flow's own controls. A HOST may still pass a step-specific
  // label (the escape beside a `Pay $635.53` button says something different);
  // these are what a component falls back to when it is not told.

  /// The forward action on a step's footer.
  String get continueAction;

  /// The footer's step-back action.
  String get backAction;

  /// The right gutter's skip.
  String get skipAction;

  /// The ghost escape — LEAVING the flow, not the step.
  String get escapeAction;

  /// Re-run a read that failed.
  String get retryAction;

  /// Empty a value that has one (the date wheel's).
  String get clearAction;

  /// Commit a sheet's value and close it.
  String get doneAction;

  /// Reopen somebody's details from a roster row.
  String get editAction;

  /// The screen-reader label on that Edit — a reader hearing four bare "Edit"s
  /// down a family roster learns nothing, so it names the person.
  String editSemantic(String name);

  /// The screen-reader label on a roster row's remove control.
  String removeSemantic(String name);

  // ── Step heads ────────────────────────────────────────────────────────────
  // The title and its one answering line, for the steps BOTH surfaces walk.
  // A step only one of them has keeps its words on that surface's own copy
  // class — there is no second voice for those to drift from, and an abstract
  // method the other surface can only answer with a lie is worse than none.
  //
  // Every one of these takes the FACTS the line interpolates, never a
  // pre-formatted sentence, so one voice can reorder or drop a clause the
  // other keeps: the member reads "Pick your membership", the desk reads
  // "Pick Marcus's plans", from the same call.

  /// One rung of the step rail, for a screen reader.
  ///
  /// The rail is drawn as discs and connectors, so a reader hearing only the
  /// rung's word learns neither where it sits nor whether it has been passed.
  /// It is structural rather than voiced — both surfaces answer it the same
  /// way — but it is still a user-facing sentence, so it lives here rather
  /// than inside the shared widget.
  String railStepSemantic({
    required int index,
    required int total,
    required String label,
    required bool done,
    required bool current,
  });

  /// The roster step — who is joining, and who pays for them.
  String get rosterStepTitle;
  String get rosterStepSubtitle;

  /// The plans step. [isGroup] is what makes naming a person mean anything on
  /// a surface that usually has only one; [firstName] may be empty.
  String planStepTitle({required String firstName, required bool isGroup});

  /// The plans step's answering line. [personIndex] is ZERO-based, so a
  /// surface that counts people prints `personIndex + 1`; a run of one person
  /// has nothing to count and says so by dropping the clause.
  String planStepSubtitle({
    required int personIndex,
    required int personCount,
  });

  /// The waivers step.
  String waiverStepTitle({required String firstName, required bool isGroup});

  /// The waivers step's answering line. [index] is ZERO-based. [planName] is
  /// the membership that REQUIRES this signature, absent while the plan is
  /// unknown.
  String waiverStepSubtitle({
    required int index,
    required int total,
    required String? planName,
    required String firstName,
  });

  /// The review step — the lineup and what it costs.
  String get reviewStepTitle;
  String reviewStepSubtitle({required bool isGroup});

  /// The settlement step. Its answering line is per-surface: the kiosk names
  /// the plan being bought, the desk names the amount, and neither is the
  /// other's sentence.
  String get paymentStepTitle;

  /// The receipt. [count] is how many memberships landed.
  String resultsStepTitle({required bool allCreated, required int count});

  /// The receipt's answering line. [amountLabel] and [cardLast4] are what
  /// actually settled, for a surface that states it; both may be absent.
  String resultsStepSubtitle({
    required bool allCreated,
    required bool isGroup,
    required String? amountLabel,
    required String? cardLast4,
  });

  // ── The roster ────────────────────────────────────────────────────────────

  /// The per-person "is this one being charged" check. [isGroup] is what makes
  /// a comparative phrase ("as well") mean anything, and [firstName] may be
  /// empty for somebody whose details step has not run yet.
  String rosterTrainingCheck({
    required String firstName,
    required bool isGroup,
  });

  /// The quiet second line for somebody with no address on file yet.
  String get rosterPendingLine;

  /// The pill on the payer's row — the fact that explains the whole screen.
  String get payingPill;

  /// The pill on a payee who already trains here.
  String get memberPill;

  /// The pill on a payee this run is creating.
  String get newcomerPill;

  /// The review block's mono label for the payer.
  String get payingEyebrow;

  /// The review block's mono label for an existing member.
  String get memberEyebrow;

  /// The review block's mono label for somebody new.
  String get newcomerEyebrow;

  /// The mark on a person whose membership already went through on an earlier
  /// attempt, so the card about to be entered is not charged for them.
  String get startedEyebrow;

  // ── Plans ─────────────────────────────────────────────────────────────────

  /// The eyebrow over a picked membership. The desk counts them (one card per
  /// picked plan); the kiosk sells one and says so in the member's voice.
  String pickedEyebrow({required int index, required int total});

  /// The tag pinned over a plan card closed to this person, when the caller
  /// has no gate reason of its own to name.
  String get planBlockedTag;

  // ── Waivers ───────────────────────────────────────────────────────────────

  /// The signing panel's banner eyebrow.
  String get signingForEyebrow;

  /// The quiet line under the name in that banner — the guardian clause.
  String get signingBannerNote;

  /// The consent tick's line. Typing a name IS the signature, and this is
  /// where that is said.
  String get signingConsentLabel;

  /// The consent tick's quieter second line.
  String get signingConsentNote;

  /// The label over the typed-name field.
  String get signerNameLabel;

  /// The waiver body could not be read. A retry, never a stop.
  String get waiverLoadFailed;

  /// The rule line under a waiver already signed during this purchase.
  String waiverSignedRule(String signerName);

  // ── Details ───────────────────────────────────────────────────────────────

  /// The date-of-birth field's label, and its sheet's title.
  String get dobLabel;

  /// The empty date field's placeholder. It must read as the same shape the
  /// chosen value renders in, or the box changes KIND when it fills.
  String get dobPlaceholder;

  /// A chosen date of birth, formatted.
  String dobDisplay(DateTime date);

  // ── Review and money ──────────────────────────────────────────────────────

  /// The review side panel's label over WHO this is.
  String get reviewPersonEyebrow;

  /// The review side panel's label over what they picked.
  String get reviewMembershipEyebrow;

  /// The group review panel's label over the whole roster.
  String get reviewGroupEyebrow;

  /// The money panel's label over the one figure coming off the card today.
  String get dueTodayEyebrow;

  /// Where payment mail reaches the payer. Only a FAILED payment is ever
  /// notified — the connected account sends nothing else — so no line here may
  /// promise a receipt.
  String failedPaymentNotice(String email);

  /// What bills again after today. [cycleWord] is the plan's own billing unit
  /// ("month", "2 months", "week"), never assumed.
  String recurringHeadline({
    required int totalMinorUnits,
    required String currency,
    required String cycleWord,
  });

  /// Who recurs and from when. In a group the names matter: a one-off pack
  /// does not recur for the child who got it. Either may be absent.
  String recurringDetail({
    required List<String> names,
    required DateTime? nextPaymentAt,
  });

  /// Why "due today" and "then $X" are different numbers. [until] is the
  /// preview's own period end; null when it names none.
  String prorationNote(DateTime? until);

  /// The statement will show TWO charges today — one string, read before the
  /// card is taken and again on the receipt after it clears.
  String get twoChargesNote;

  // ── The card ──────────────────────────────────────────────────────────────

  /// The card chip with no last four known.
  String get cardOnFile;

  /// The card chip naming which card is about to be (or has just been) charged.
  String cardEnding(String last4);

  /// The trust strip's first line — what happens to the number.
  String get secureStripTitle;

  /// The trust strip's second line — who does NOT see it. It names the gym,
  /// and degrades rather than inventing one.
  String secureStripDetail(String? gymName);

  // ── Results ───────────────────────────────────────────────────────────────

  /// What HAPPENED to one membership, as a consequence rather than an error
  /// code. `unknown` claims nothing about money in either direction.
  String resultConsequence(MemberMembershipsStartStatus status);
}
