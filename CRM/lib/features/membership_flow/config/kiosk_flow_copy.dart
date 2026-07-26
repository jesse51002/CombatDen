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
