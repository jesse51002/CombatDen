import 'package:intl/intl.dart';

import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_status.dart';
import 'package:crm/features/membership_flow/config/flow_copy.dart';
import 'package:crm/features/membership_flow/domain/name_labels.dart';

/// The MEMBER's voice — the words on the front-desk iPad.
///
/// It addresses the person standing at the screen in the first person ("I'm
/// getting a membership", "we'll email you"), because the member is the one
/// tapping. Two rules run through all of it:
///
/// - **It states consequences, never errors.** A failed row says what it means
///   for the person's money, not what the backend returned; a raw error is
///   right at a staff desk and wrong in a lobby.
/// - **It promises only what is true.** No line here mentions a receipt —
///   CombatDen has no mailer and the connected account notifies on a FAILED
///   payment only — and nothing claims a charge the backend would not confirm.
class KioskFlowCopy extends MembershipFlowCopy {
  const KioskFlowCopy();

  /// The date a recurring charge first lands, and the day a part period runs
  /// up to. One format for both, so two lines about the same date agree.
  static final DateFormat _day = DateFormat('d MMMM y');

  /// A chosen date of birth, matching the box's `MM / DD / YYYY` placeholder
  /// so the field reads the same empty or full.
  static final DateFormat _dob = DateFormat('MM / dd / yyyy');

  /// What every recurring line ends with: the card it lands on and how to
  /// stop it. The escape route belongs in the sentence that creates the
  /// obligation, not on a later screen.
  static const String _recurringTail =
      'On the same card. Cancel any time at the front desk — no '
      'notice period.';

  @override
  String get continueAction => 'Continue';

  @override
  String get backAction => 'Back';

  @override
  String get skipAction => 'Skip for now';

  @override
  String get escapeAction => 'Start over';

  @override
  String get retryAction => 'Try again';

  @override
  String get clearAction => 'Clear';

  @override
  String get doneAction => 'Done';

  @override
  String get editAction => 'Edit';

  @override
  String editSemantic(String name) => 'Edit $name';

  @override
  String removeSemantic(String name) => 'Remove $name';

  // ── Step heads ────────────────────────────────────────────────────────────
  // The member is reading these from about two metres away, standing up, with
  // somebody behind them in the lobby. So a head states the ONE thing this
  // screen is for and its answering line states the consequence — never a
  // second instruction, and never a fact only staff would want.

  /// Structural rather than voiced: a reader needs the same three facts on
  /// either surface, so this reads identically to the desk's.
  @override
  String railStepSemantic({
    required int index,
    required int total,
    required String label,
    required bool done,
    required bool current,
  }) {
    final state = current
        ? 'current step'
        : done
            ? 'completed'
            : 'upcoming';
    return 'Step ${index + 1} of $total, $label, $state';
  }

  @override
  String get rosterStepTitle => 'Anyone else joining?';

  /// Names the three families that actually walk in, then the fact that
  /// explains the whole flow: one card, everybody on it.
  @override
  String get rosterStepSubtitle =>
      'Add the people you\'re paying for — family, a partner, a '
      'friend. You pay for everyone on one card.';

  /// A solo signup keeps the warm second person; a GROUP names whose turn it
  /// is on every one, the payer's included — an unnamed turn in a run of named
  /// ones is where the wrong child gets the wrong membership.
  @override
  String planStepTitle({required String firstName, required bool isGroup}) {
    if (!isGroup) return 'Pick your membership';
    final first = firstName.trim();
    return first.isEmpty
        ? 'Pick their membership'
        : 'Pick $first\'s membership';
  }

  /// The rule that makes picking low-stakes, and — only when there is more
  /// than one person to count — where in the run they are. One person has
  /// nothing to count, so the clause is dropped rather than reading "1 of 1".
  @override
  String planStepSubtitle({
    required int personIndex,
    required int personCount,
  }) {
    const rule = 'You can change it any time at the front desk · no lock-in';
    if (personCount < 2) return rule;
    return 'Person ${personIndex + 1} of $personCount · $rule';
  }

  /// Solo reads as the promise it is — one signature, then you train. A group
  /// names the person instead, for the same reason the plans step does.
  @override
  String waiverStepTitle({required String firstName, required bool isGroup}) {
    if (!isGroup) return 'One signature and you\'re in';
    final first = firstName.trim();
    if (first.isEmpty) return 'One signature and you\'re in';
    return '$first\'s waiver';
  }

  /// The plan that ASKED for this document, then where the member is in the
  /// run — somebody with three to sign is never surprised by the second. The
  /// name is already pinned in the strip above, so this line never repeats it.
  @override
  String waiverStepSubtitle({
    required int index,
    required int total,
    required String? planName,
    required String firstName,
  }) {
    final position = '${index + 1} of $total';
    final plan = planName?.trim() ?? '';
    if (plan.isEmpty) return 'Waiver $position';
    return 'Required for $plan · waiver $position';
  }

  /// Button-agnostic: the committing label below says what is being signed and
  /// for how much, so naming it here would start lying the moment a trial cart
  /// changes the verb.
  @override
  String get reviewStepTitle => 'Check this over';

  /// The one thing a member wants to know before reading a total back: none of
  /// this has happened yet. A group hears whose card it all lands on first.
  @override
  String reviewStepSubtitle({required bool isGroup}) => isGroup
      ? 'One card covers everyone. Nothing is charged until you '
          'confirm.'
      : 'Nothing is charged until you confirm.';

  /// The kiosk names the THING, not the act: nothing is charged on this step,
  /// and "Payment" over a card field reads as the charge itself.
  @override
  String get paymentStepTitle => 'Your card';

  /// The outcome, said as a consequence. The kiosk never counts the rows — the
  /// receipt below already lists them by name, and a member reading "All 3
  /// memberships started" is being handed the desk's fact.
  @override
  String resultsStepTitle({required bool allCreated, required int count}) =>
      allCreated ? 'You\'re all set' : 'Some of these didn\'t go through';

  /// A partial points at the one action that is safe (the same card, the rows
  /// that failed); a clean run says what changed today. Neither states an
  /// amount — the money already moved, and re-quoting it here invites a member
  /// to re-read a charge they cannot now change.
  @override
  String resultsStepSubtitle({
    required bool allCreated,
    required bool isGroup,
    required String? amountLabel,
    required String? cardLast4,
  }) {
    if (!allCreated) {
      return 'Have a look — you can try the rest on the same card.';
    }
    return isGroup
        ? 'Every membership below started today.'
        : 'Your membership started today.';
  }

  // ── Kiosk-only steps ──────────────────────────────────────────────────────
  // Steps the desk does not walk, so their words live HERE rather than on the
  // shared interface: an abstract method the other surface could only answer
  // with an invented sentence is worse than no method at all. The desk has no
  // fork screen, no duplicate confirm and no "who's paying" pick — staff are
  // already looking at the member's own record when they start the wizard.

  /// The lane's first screen. It greets by NAME where there is one — the
  /// member's first read is "am I in the right place" — and degrades to the
  /// bare welcome rather than printing an empty gym.
  String entryStepTitle(String? gymName) {
    final gym = gymName?.trim() ?? '';
    return gym.isEmpty ? 'Welcome in' : 'Welcome to $gym';
  }

  /// Frames the fork as a fact about the READER, not a menu of actions: both
  /// halves lead into the same lane.
  String get entryStepSubtitle => 'Two ways in. Which one are you?';

  /// The first form. It states the cost in TIME, because that is the objection
  /// somebody standing in a lobby actually has.
  String get detailsStepTitle => 'Let\'s get you started';

  String get detailsStepSubtitle => 'Two minutes, and you can train today.';

  /// An existing member identifying themselves rather than typing a second
  /// account into being — the line says which name to type and what happens
  /// with it, so nobody wonders whether they are signing up twice.
  String get identifyStepTitle => 'Find your name';

  String get identifyStepSubtitle =>
      'Type the name you train under. We\'ll use your account '
      'instead of making a second one.';

  /// The PAYEE duplicate, offered back for confirmation. Searching is a
  /// different screen wearing the same step: it asks for a name, where the
  /// confirm asks about one already found.
  String matchStepTitle({
    required bool searching,
    required String firstName,
  }) =>
      searching ? 'Find them by name' : 'Is this the same $firstName?';

  /// Reusing an existing account is the right outcome for a payee (they pay
  /// nothing), so both branches say what will happen rather than warning.
  String matchStepSubtitle({
    required bool searching,
    required String fullName,
  }) =>
      searching
          ? 'Pick the person you\'re adding. We\'ll use their account '
              'instead of making a second one.'
          : 'We already train a $fullName. If it\'s them, we\'ll '
              'use their account instead of making a second one.';

  String get payerPickStepTitle => 'Who\'s paying?';

  /// Two situations, one screen. With a payer seated this is a CHANGE, so the
  /// line opens on the roster already in front of them; with none (the
  /// previous payer was removed) it is the required choice. Both end on the
  /// same promise, because the card and the coverage are what the member is
  /// actually deciding about.
  String payerPickStepSubtitle({required bool hasPayer}) => hasPayer
      ? 'Pick anyone here, or find another member. They enter their '
          'card at the end, and everyone on the list is on it.'
      : 'Pick who pays for everyone here. They enter their card at '
          'the end, and everyone on the list is on it.';

  /// The PAYER's own duplicate. Never a leak: the card shows the person their
  /// own account back, masked, and still asks.
  String get payerMatchStepTitle => 'Is this you?';

  /// On the identify route they have already said they have an account, so the
  /// line reassures that nothing new is being made; on the duplicate route the
  /// account itself is the news and has to be said first.
  String payerMatchStepSubtitle({required bool fromIdentify}) => fromIdentify
      ? 'Tap yes and we\'ll use this account. Nothing new gets '
          'created.'
      : 'You already have an account here. If it\'s you, we\'ll use '
          'it instead of making a second one.';

  /// The authorized-payer agreement, one per payee. It names the payee in the
  /// TITLE because the signer is always the payer — the one screen in the run
  /// where the person typing is not the person the document is about.
  String payerWaiverStepTitle(String firstName) =>
      'You\'re paying for $firstName';

  /// This run counts PEOPLE, not documents, and names who is still to come so
  /// a parent with three to authorise can see the end of it. [remaining] is
  /// the queue from here on, this person first; at most the next two are read
  /// out, and one name alone says nothing the position does not.
  String payerWaiverStepSubtitle({
    required int index,
    required int total,
    required List<String> remaining,
  }) {
    final position = 'Person ${index + 1} of $total';
    if (remaining.length < 2) return position;
    return '$position · ${remaining.first}, then ${remaining[1]}';
  }

  /// The optional block. A payee's turn names them, since the roster is what
  /// the member is working through; the payer's own turn is simply theirs.
  String optionalStepTitle({
    required bool payee,
    required String firstName,
  }) =>
      payee ? 'A bit more about $firstName' : 'A bit more about you';

  /// The optionality, said ONCE where it is read. A matched existing member
  /// gets the honest reason their form is blank instead — a lobby iPad never
  /// prints another member's stored details, and saying so beats a form that
  /// looks broken. Otherwise it names who sees this, which is the question
  /// somebody typing their address on a shared screen is really asking.
  String optionalStepSubtitle({
    required bool wasExisting,
    required bool payee,
    required String firstName,
    required int personIndex,
    required int personCount,
    required String? gymName,
  }) {
    if (wasExisting) {
      return '$firstName already has details with us — we don\'t '
          'show them on a shared screen.';
    }
    if (payee) {
      return 'Person ${personIndex + 1} of $personCount · all optional';
    }
    final gym = gymName?.trim() ?? '';
    return gym.isEmpty
        ? 'Only gym staff sees this · all of it is optional'
        : 'Only $gym staff sees this · all of it is optional';
  }

  @override
  String rosterTrainingCheck({
    required String firstName,
    required bool isGroup,
  }) {
    if (!isGroup) return 'I\'m getting a membership';
    final who = firstName.trim().isEmpty ? 'This person' : firstName;
    return '$who is getting a membership as well';
  }

  @override
  String get rosterPendingLine => 'Added just now';

  @override
  String get payingPill => 'Paying';

  @override
  String get memberPill => 'Member';

  @override
  String get newcomerPill => 'New';

  @override
  String get payingEyebrow => 'PAYING';

  @override
  String get memberEyebrow => 'MEMBER';

  @override
  String get newcomerEyebrow => 'NEW';

  @override
  String get startedEyebrow => 'STARTED';

  /// The kiosk sells ONE membership per person, so it never counts them — the
  /// index and total are the desk's fact.
  @override
  String pickedEyebrow({required int index, required int total}) =>
      'YOU\'VE PICKED';

  @override
  String get planBlockedTag => 'Already used';

  @override
  String get signingForEyebrow => 'SIGNING FOR';

  @override
  String get signingBannerNote =>
      'Signed by you, or by a parent / legal guardian on your behalf.';

  @override
  String get signingConsentLabel =>
      'I have read this waiver and agree to it. Typing my '
      'name counts as my signature.';

  @override
  String get signingConsentNote =>
      'Your name appears in the document as you type it. A '
      'copy goes to your email.';

  @override
  String get signerNameLabel => 'Type your full legal name';

  @override
  String get waiverLoadFailed => 'We couldn\'t load the waiver just now.';

  @override
  String waiverSignedRule(String signerName) => 'Signed today by $signerName';

  @override
  String get dobLabel => 'Date of birth';

  @override
  String get dobPlaceholder => 'MM / DD / YYYY';

  @override
  String dobDisplay(DateTime date) => _dob.format(date);

  @override
  String get reviewPersonEyebrow => 'YOU';

  @override
  String get reviewMembershipEyebrow => 'YOUR MEMBERSHIP';

  @override
  String get reviewGroupEyebrow => 'WHO\'S JOINING';

  @override
  String get dueTodayEyebrow => 'DUE TODAY';

  @override
  String failedPaymentNotice(String email) =>
      'If a payment ever fails, we\'ll email you at $email.';

  @override
  String recurringHeadline({
    required int totalMinorUnits,
    required String currency,
    required String cycleWord,
  }) =>
      'Then ${formatMinorUnits(
        totalMinorUnits,
        currency: currency,
      )} each $cycleWord';

  @override
  String recurringDetail({
    required List<String> names,
    required DateTime? nextPaymentAt,
  }) {
    final when =
        nextPaymentAt == null ? null : _day.format(nextPaymentAt.toLocal());
    final who = names.isEmpty ? null : flowNameList(names);
    if (who != null && when != null) {
      return '$who, from $when. $_recurringTail';
    }
    if (who != null) return '$who. $_recurringTail';
    if (when != null) return 'Next charge $when. $_recurringTail';
    return _recurringTail;
  }

  @override
  String prorationNote(DateTime? until) {
    final when = until == null ? null : _day.format(until.toLocal());
    return when == null
        ? 'Today is a part-period charge — it covers the rest of this '
            'billing period only.'
        : 'Today is a part-period charge — it covers you up to $when. The '
            'full amount starts then.';
  }

  @override
  String get twoChargesNote =>
      'This shows up as two separate charges today — one for the one-off '
      'purchase and one for the membership.';

  @override
  String get cardOnFile => 'Card on file';

  @override
  String cardEnding(String last4) => 'Card ending $last4';

  @override
  String get secureStripTitle => 'Encrypted and sent straight to Stripe';

  @override
  String secureStripDetail(String? gymName) {
    final gym = gymName?.trim() ?? '';
    final who = gym.isEmpty ? 'This gym' : gym;
    return '$who never sees your card number, and neither does this iPad.';
  }

  @override
  String resultConsequence(MemberMembershipsStartStatus status) {
    return switch (status) {
      MemberMembershipsStartStatus.created => 'Started today',
      MemberMembershipsStartStatus.failed =>
        'Not started — nothing was charged for this one.',
      MemberMembershipsStartStatus.unknown =>
        'We couldn\'t confirm this one — the desk can check it for you.',
    };
  }
}
