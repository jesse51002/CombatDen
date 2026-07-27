import 'package:intl/intl.dart';

import 'package:crm/core/utils/money.dart';
import 'package:crm/features/member_details/data/models/member_memberships_start_status.dart';
import 'package:crm/features/membership_flow/config/flow_copy.dart';
import 'package:crm/features/membership_flow/domain/name_labels.dart';

/// The STAFF voice — the words in the desk's start-memberships dialog.
///
/// Same flow, different reader. Three things change:
///
/// - **The third person.** Staff are selling ON somebody's behalf, so nothing
///   here says "you" or "your"; a line reading "your membership" over a child's
///   row at the desk names the wrong person.
/// - **Facts a member never needs.** The desk picks several memberships per
///   person, so a picked card is COUNTED (`MEMBERSHIP 1 OF 2`) where the kiosk
///   sells one and says so plainly.
/// - **A different room.** The trust strip names the browser, not the iPad,
///   and a row that could not be confirmed points staff at the member's own
///   profile rather than at the desk they are already standing behind.
///
/// The two implementations of [MembershipFlowCopy] are the only place either
/// surface's wording lives, which is what stops a change landing on one.
class StaffFlowCopy extends MembershipFlowCopy {
  const StaffFlowCopy();

  /// The date a recurring charge first lands, and the day a part period runs
  /// up to. The same format the kiosk uses — a date is not a matter of voice.
  static final DateFormat _day = DateFormat('d MMMM y');

  static final DateFormat _dob = DateFormat('MM / dd / yyyy');

  /// What every recurring line ends with. Identical to the member's, because
  /// it is the promise being made about the gym's own cancellation policy.
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

  /// Named for the RUN rather than for the record: nothing on this roster
  /// deletes a member, and the label has to say which of the two it is.
  @override
  String removeSemantic(String name) => 'Remove $name from this run';

  // ── Step heads ────────────────────────────────────────────────────────────

  /// Position, then name, then state — the order a reader needs them in to
  /// skip the rail once they have heard where they are.
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
  String get rosterStepTitle => 'Who\'s joining?';

  /// The fact that explains the whole screen, then the one control on it.
  @override
  String get rosterStepSubtitle =>
      'Everything here bills to one card. Tick whoever\'s getting a '
      'membership.';

  @override
  String planStepTitle({required String firstName, required bool isGroup}) {
    final first = firstName.trim();
    return first.isEmpty ? 'Pick their plans' : 'Pick $first\'s plans';
  }

  /// Plural where the kiosk is singular: the desk sells several memberships
  /// to one person, and the line has to say so before the second card
  /// appears.
  @override
  String planStepSubtitle({
    required int personIndex,
    required int personCount,
  }) {
    const rule = 'add as many as they need — one-time packs stack';
    if (personCount < 2) return 'Pick a plan · $rule';
    return 'Person ${personIndex + 1} of $personCount · $rule';
  }

  /// The desk signs on somebody's behalf, so the title names the RUN's job
  /// rather than the person — the identity strip beside it names them.
  @override
  String waiverStepTitle({
    required String firstName,
    required bool isGroup,
  }) =>
      'Signatures needed';

  @override
  String waiverStepSubtitle({
    required int index,
    required int total,
    required String? planName,
    required String firstName,
  }) {
    final position = 'Waiver ${index + 1} of $total';
    final plan = planName?.trim() ?? '';
    final first = firstName.trim();
    if (plan.isEmpty) return position;
    if (first.isEmpty) return '$position · required for $plan';
    return '$position · required for $first\'s $plan';
  }

  @override
  String get reviewStepTitle => 'Review & charges';

  /// Staff are about to read a number back to somebody, so the line says
  /// exactly when the money moves — which is not on this screen.
  @override
  String reviewStepSubtitle({required bool isGroup}) =>
      'Nothing is charged until payment is taken on the next step.';

  @override
  String get paymentStepTitle => 'How is this paid?';

  @override
  String resultsStepTitle({required bool allCreated, required int count}) {
    if (!allCreated) return 'Some of these didn\'t go through';
    return count == 1
        ? 'The membership started'
        : 'All $count memberships started';
  }

  @override
  String resultsStepSubtitle({
    required bool allCreated,
    required bool isGroup,
    required String? amountLabel,
    required String? cardLast4,
  }) {
    if (!allCreated) return 'Have a look — the rest can go on the same card.';
    final amount = amountLabel?.trim() ?? '';
    if (amount.isEmpty) return 'Nothing was charged for this run.';
    final last4 = cardLast4?.trim() ?? '';
    return last4.isEmpty
        ? '$amount charged.'
        : '$amount charged to the card ending $last4.';
  }

  /// One line either way. Staff read a column of rows and compare them, so a
  /// row whose wording changes with the roster's size is harder to scan, not
  /// friendlier — the comparative phrasing is the member's, addressed to one
  /// person about their own family.
  @override
  String rosterTrainingCheck({
    required String firstName,
    required bool isGroup,
  }) =>
      'Getting a membership';

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

  /// The desk sells SEVERAL memberships to one person, so each picked card
  /// says which of them it is — two cards with the same eyebrow would leave
  /// the discounts on them ambiguous.
  @override
  String pickedEyebrow({required int index, required int total}) =>
      'MEMBERSHIP $index OF $total';

  /// The desk's gates name their own reason ("Already on this plan"); this is
  /// only what a card falls back to when the caller has none.
  @override
  String get planBlockedTag => 'Not available';

  @override
  String get signingForEyebrow => 'SIGNING FOR';

  @override
  String get signingBannerNote =>
      'Signed by the member, or by a parent / legal guardian on their '
      'behalf.';

  @override
  String get signingConsentLabel =>
      'They have read this waiver and agree to it. Typing their name '
      'counts as their signature.';

  @override
  String get signingConsentNote =>
      'The name appears in the document as it is typed. A copy goes to '
      'their email.';

  @override
  String get signerNameLabel => 'Type the full legal name';

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
  String get reviewPersonEyebrow => 'MEMBER';

  @override
  String get reviewMembershipEyebrow => 'MEMBERSHIP';

  @override
  String get reviewGroupEyebrow => 'WHO\'S GETTING WHAT';

  @override
  String get dueTodayEyebrow => 'DUE TODAY';

  /// Third person, and still only a FAILURE notice: the connected account
  /// sends nothing else, so this line may not imply a receipt to staff either.
  @override
  String failedPaymentNotice(String email) =>
      'If a payment fails, the payer is emailed at $email.';

  /// "More" is the desk's word: this run ADDS to a recurring bill the payer
  /// may already have, and staff are answering "what does this change".
  @override
  String recurringHeadline({
    required int totalMinorUnits,
    required String currency,
    required String cycleWord,
  }) =>
      'Then ${formatMinorUnits(
        totalMinorUnits,
        currency: currency,
      )} more each $cycleWord';

  @override
  String recurringDetail({
    required List<String> names,
    required DateTime? nextPaymentAt,
  }) {
    final when =
        nextPaymentAt == null ? null : _day.format(nextPaymentAt.toLocal());
    final who = names.isEmpty ? null : flowNameList(names);
    if (who != null && when != null) {
      return 'For $who. First full bill $when. $_recurringTail';
    }
    if (who != null) return 'For $who. $_recurringTail';
    if (when != null) return 'First full bill $when. $_recurringTail';
    return _recurringTail;
  }

  @override
  String prorationNote(DateTime? until) {
    final when = until == null ? null : _day.format(until.toLocal());
    return when == null
        ? 'Today is a part-period charge — it covers the rest of this '
            'billing period only.'
        : 'Today is a part-period charge — it covers up to $when. The full '
            'amount starts then.';
  }

  @override
  String get twoChargesNote =>
      'Two separate charges land today — one for the one-off purchases and '
      'one for the membership.';

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
    return '$who never sees the card number, and neither does this browser.';
  }

  /// A row the backend would not confirm sends staff to the member's own
  /// profile — the one place that can answer it — rather than to the desk they
  /// are already standing behind.
  @override
  String resultConsequence(MemberMembershipsStartStatus status) {
    return switch (status) {
      MemberMembershipsStartStatus.created => 'Started today',
      MemberMembershipsStartStatus.failed =>
        'Not started — nothing was charged for this one.',
      MemberMembershipsStartStatus.unknown =>
        'We couldn\'t confirm this one — check this member\'s profile '
            'before retrying it.',
    };
  }
}
