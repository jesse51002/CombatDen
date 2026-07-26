import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/member_details/data/models/member_memberships_start_status.dart';
import 'package:crm/features/member_details/presentation/dialogs/start_memberships/start_memberships_wizard.dart';

import '../../../bloc/membership_wizard/membership_wizard_fixtures.dart';

/// When the run tells the page behind to re-read.
///
/// The page underneath is showing the very memberships a start just created, so
/// a landing it never hears about is a page that quietly lies until somebody
/// reloads it by hand.
void main() {
  final partial = startResponse([
    resultItem(memberId: 'm-payer', planId: 'plan-a'),
    resultItem(
      memberId: 'm-kid',
      planId: 'plan-b',
      status: MemberMembershipsStartStatus.failed,
    ),
  ]);
  final afterRetry = startResponse([
    resultItem(memberId: 'm-payer', planId: 'plan-a'),
    resultItem(memberId: 'm-kid', planId: 'plan-b'),
  ]);

  test('an attempt still in flight announces nothing', () {
    expect(announcesNewLanding(null, null), isFalse);
    expect(
      announcesNewLanding(partial, null),
      isFalse,
      reason: 'a fresh attempt clears the result before it posts',
    );
  });

  test('the first landing announces', () {
    expect(announcesNewLanding(null, partial), isTrue);
  });

  test('a retry that creates the rest announces AGAIN', () {
    expect(
      announcesNewLanding(partial, afterRetry),
      isTrue,
      reason: 'the page is showing the partial and is missing what the retry '
          'created',
    );
  });

  test('an attempt that produces no breakdown of its own announces nothing',
      () {
    // A decline, a network failure, and a 409 replay all RESTORE the previous
    // response rather than building a new one, so the page behind is not
    // re-read once per attempt.
    expect(announcesNewLanding(partial, partial), isFalse);
  });

  test('identity, not value: an equal-looking SECOND response still announces',
      () {
    final again = startResponse([
      resultItem(memberId: 'm-payer', planId: 'plan-a'),
      resultItem(
        memberId: 'm-kid',
        planId: 'plan-b',
        status: MemberMembershipsStartStatus.failed,
      ),
    ]);
    expect(
      announcesNewLanding(partial, again),
      isTrue,
      reason: 'a genuinely new response is a genuinely new landing, whatever '
          'it happens to contain',
    );
  });
}
