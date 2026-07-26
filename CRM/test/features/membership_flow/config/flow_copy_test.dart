import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/member_details/data/models/member_memberships_start_status.dart';
import 'package:crm/features/membership_flow/config/flow_copy.dart';
import 'package:crm/features/membership_flow/config/kiosk_flow_copy.dart';
import 'package:crm/features/membership_flow/config/staff_flow_copy.dart';

/// The two voices.
///
/// [KioskFlowCopy] is pinned BYTE-FOR-BYTE against what the kiosk shipped
/// before the copy layer existed: extracting a string is a refactor, and a
/// refactor that changes a word on a member-facing screen is a rendering
/// change nobody asked for. Every literal below was lifted from the widget it
/// came out of.
///
/// [StaffFlowCopy] is checked for the things that make it a different VOICE
/// rather than the same sentences reformatted — third person, and the facts a
/// desk needs that a member does not.
void main() {
  const kiosk = KioskFlowCopy();
  const staff = StaffFlowCopy();

  group('the kiosk voice is unchanged, byte for byte', () {
    test('the roster check earns "as well" only beside somebody else', () {
      expect(
        kiosk.rosterTrainingCheck(firstName: 'Ella', isGroup: false),
        'I\'m getting a membership',
      );
      expect(
        kiosk.rosterTrainingCheck(firstName: 'Ella', isGroup: true),
        'Ella is getting a membership as well',
      );
    });

    test('a person with no first name yet degrades rather than blanking', () {
      expect(
        kiosk.rosterTrainingCheck(firstName: '   ', isGroup: true),
        'This person is getting a membership as well',
      );
    });

    test('the roster marks and pills', () {
      expect(kiosk.rosterPendingLine, 'Added just now');
      expect(kiosk.payingPill, 'Paying');
      expect(kiosk.memberPill, 'Member');
      expect(kiosk.newcomerPill, 'New');
      expect(kiosk.payingEyebrow, 'PAYING');
      expect(kiosk.memberEyebrow, 'MEMBER');
      expect(kiosk.newcomerEyebrow, 'NEW');
      expect(kiosk.startedEyebrow, 'STARTED');
      expect(kiosk.editAction, 'Edit');
      expect(kiosk.editSemantic('Ella Bell'), 'Edit Ella Bell');
      expect(kiosk.removeSemantic('Ella Bell'), 'Remove Ella Bell');
    });

    test('the picked banner never counts', () {
      expect(kiosk.pickedEyebrow(index: 1, total: 1), 'YOU\'VE PICKED');
      expect(kiosk.pickedEyebrow(index: 2, total: 3), 'YOU\'VE PICKED');
    });

    test('the review and money panels', () {
      expect(kiosk.reviewPersonEyebrow, 'YOU');
      expect(kiosk.reviewMembershipEyebrow, 'YOUR MEMBERSHIP');
      expect(kiosk.reviewGroupEyebrow, 'WHO\'S JOINING');
      expect(kiosk.dueTodayEyebrow, 'DUE TODAY');
      expect(
        kiosk.waiverSignedRule('Marcus Bell'),
        'Signed today by Marcus Bell',
      );
      expect(
        kiosk.failedPaymentNotice('m@bell.family'),
        'If a payment ever fails, we\'ll email you at m@bell.family.',
      );
      expect(
        kiosk.twoChargesNote,
        'This shows up as two separate charges today — one for the one-off '
        'purchase and one for the membership.',
      );
    });

    test('the recurring headline names the plan\'s own cycle', () {
      expect(
        kiosk.recurringHeadline(
          totalMinorUnits: 10420,
          currency: 'usd',
          cycleWord: 'month',
        ),
        'Then \$104.20 each month',
      );
      expect(
        kiosk.recurringHeadline(
          totalMinorUnits: 2500,
          currency: 'usd',
          cycleWord: '2 weeks',
        ),
        'Then \$25.00 each 2 weeks',
      );
    });

    test('the recurring detail states only what it knows', () {
      final when = DateTime(2026, 8, 1);
      const tail = 'On the same card. Cancel any time at the front desk — no '
          'notice period.';
      expect(
        kiosk.recurringDetail(names: ['Ella', 'Theo'], nextPaymentAt: when),
        'Ella and Theo, from 1 August 2026. $tail',
      );
      expect(
        kiosk.recurringDetail(names: ['Ella'], nextPaymentAt: null),
        'Ella. $tail',
      );
      expect(
        kiosk.recurringDetail(names: const [], nextPaymentAt: when),
        'Next charge 1 August 2026. $tail',
      );
      expect(
        kiosk.recurringDetail(names: const [], nextPaymentAt: null),
        tail,
      );
    });

    test('the proration note', () {
      expect(
        kiosk.prorationNote(null),
        'Today is a part-period charge — it covers the rest of this '
        'billing period only.',
      );
      expect(
        kiosk.prorationNote(DateTime(2026, 8, 1)),
        'Today is a part-period charge — it covers you up to 1 August 2026. '
        'The full amount starts then.',
      );
    });

    test('the card chip and the trust strip', () {
      expect(kiosk.cardOnFile, 'Card on file');
      expect(kiosk.cardEnding('4242'), 'Card ending 4242');
      expect(kiosk.secureStripTitle, 'Encrypted and sent straight to Stripe');
      expect(
        kiosk.secureStripDetail('Iron Den'),
        'Iron Den never sees your card number, and neither does this iPad.',
      );
      expect(
        kiosk.secureStripDetail('  '),
        'This gym never sees your card number, and neither does this iPad.',
      );
    });

    test('a result row states the consequence, never an error', () {
      expect(
        kiosk.resultConsequence(MemberMembershipsStartStatus.created),
        'Started today',
      );
      expect(
        kiosk.resultConsequence(MemberMembershipsStartStatus.failed),
        'Not started — nothing was charged for this one.',
      );
      expect(
        kiosk.resultConsequence(MemberMembershipsStartStatus.unknown),
        'We couldn\'t confirm this one — the desk can check it for you.',
      );
    });

    test('the signing panel and the waiver failure', () {
      expect(kiosk.signingForEyebrow, 'SIGNING FOR');
      expect(
        kiosk.signingBannerNote,
        'Signed by you, or by a parent / legal guardian on your behalf.',
      );
      expect(
        kiosk.signingConsentLabel,
        'I have read this waiver and agree to it. Typing my name counts as '
        'my signature.',
      );
      expect(
        kiosk.signingConsentNote,
        'Your name appears in the document as you type it. A copy goes to '
        'your email.',
      );
      expect(kiosk.signerNameLabel, 'Type your full legal name');
      expect(kiosk.waiverLoadFailed, 'We couldn\'t load the waiver just now.');
    });

    test('the footer and the field defaults', () {
      expect(kiosk.continueAction, 'Continue');
      expect(kiosk.backAction, 'Back');
      expect(kiosk.skipAction, 'Skip for now');
      expect(kiosk.escapeAction, 'Start over');
      expect(kiosk.retryAction, 'Try again');
      expect(kiosk.clearAction, 'Clear');
      expect(kiosk.doneAction, 'Done');
      expect(kiosk.dobLabel, 'Date of birth');
      expect(kiosk.dobPlaceholder, 'MM / DD / YYYY');
      expect(kiosk.dobDisplay(DateTime(1994, 3, 7)), '03 / 07 / 1994');
      expect(kiosk.planBlockedTag, 'Already used');
    });
  });

  group('the staff voice is a different voice, not a reformat', () {
    test('nothing addresses the reader as the member', () {
      final firstPerson = RegExp(r"\b(you|your|you're|we'll|I'm)\b");
      final lines = <String>[
        staff.rosterTrainingCheck(firstName: 'Ella', isGroup: true),
        staff.reviewPersonEyebrow,
        staff.reviewMembershipEyebrow,
        staff.reviewGroupEyebrow,
        staff.signingBannerNote,
        staff.signingConsentLabel,
        staff.signingConsentNote,
        staff.signerNameLabel,
        staff.failedPaymentNotice('m@bell.family'),
        staff.secureStripDetail('Iron Den'),
        staff.twoChargesNote,
        staff.resultConsequence(MemberMembershipsStartStatus.unknown),
      ];
      for (final line in lines) {
        expect(
          firstPerson.hasMatch(line.toLowerCase()),
          isFalse,
          reason: 'the desk sells on somebody else\'s behalf: "$line"',
        );
      }
    });

    test('a picked membership is COUNTED, because the desk sells several', () {
      expect(staff.pickedEyebrow(index: 1, total: 2), 'MEMBERSHIP 1 OF 2');
      expect(staff.pickedEyebrow(index: 2, total: 2), 'MEMBERSHIP 2 OF 2');
    });

    test('the roster check does not change with the roster\'s size', () {
      expect(
        staff.rosterTrainingCheck(firstName: 'Ella', isGroup: false),
        staff.rosterTrainingCheck(firstName: 'Ella', isGroup: true),
      );
    });

    test('remove says which of the two removals it is', () {
      expect(
        staff.removeSemantic('Ella Bell'),
        'Remove Ella Bell from this run',
      );
    });

    test('the trust strip names the room it is actually in', () {
      expect(staff.secureStripDetail('Iron Den'), contains('browser'));
      expect(staff.secureStripDetail('Iron Den'), isNot(contains('iPad')));
    });

    test('an unconfirmed row points staff at the profile that answers it', () {
      expect(
        staff.resultConsequence(MemberMembershipsStartStatus.unknown),
        contains('profile'),
      );
    });

    test('the recurring headline says what this run ADDS', () {
      expect(
        staff.recurringHeadline(
          totalMinorUnits: 10420,
          currency: 'usd',
          cycleWord: 'month',
        ),
        'Then \$104.20 more each month',
      );
    });

    test('a date reads the same in both voices — it is not a matter of tone',
        () {
      final when = DateTime(2026, 8, 1);
      expect(staff.recurringDetail(names: const [], nextPaymentAt: when),
          contains('1 August 2026'));
      expect(staff.prorationNote(when), contains('1 August 2026'));
      expect(staff.dobDisplay(DateTime(1994, 3, 7)), '03 / 07 / 1994');
    });
  });

  test('both surfaces answer the WHOLE interface', () {
    // A missing method is a compile error, which is the point of an abstract
    // class over a map — this only pins that both are the same type, so a
    // method added later cannot be answered by one of them.
    const List<MembershipFlowCopy> voices = [kiosk, staff];
    expect(voices, hasLength(2));
  });
}
