import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/member_details/presentation/dialogs/start_memberships/authorize_direction.dart';

void main() {
  group('resolveAuthorizeParties', () {
    test('addPayee: the anchor is the payer, the other is the payee', () {
      final p = resolveAuthorizeParties(
        direction: AuthorizeDirection.addPayee,
        anchorId: 'anchor',
        anchorName: 'Ann Anchor',
        otherId: 'other',
        otherName: 'Otto Other',
      );

      expect(p.payerId, 'anchor');
      expect(p.payerName, 'Ann Anchor');
      expect(p.payeeId, 'other');
      expect(p.payeeName, 'Otto Other');
    });

    test('addPayer INVERTS it: the other pays for the anchor', () {
      // The payer step's direction — the added person becomes the PAYER and
      // the launch member (anchor) is the PAYEE whose waiver is signed.
      final p = resolveAuthorizeParties(
        direction: AuthorizeDirection.addPayer,
        anchorId: 'launch',
        anchorName: 'Lee Launch',
        otherId: 'newpayer',
        otherName: 'Nia Payer',
      );

      expect(p.payerId, 'newpayer');
      expect(p.payerName, 'Nia Payer');
      expect(p.payeeId, 'launch');
      expect(p.payeeName, 'Lee Launch');
    });
  });

  group('isAlreadyRelated', () {
    test('true for a member already in the related set', () {
      expect(
        isAlreadyRelated(
          anchorId: 'launch',
          relatedIds: const {'p1', 'p2'},
          memberId: 'p2',
        ),
        isTrue,
      );
    });

    test('true for the anchor itself', () {
      expect(
        isAlreadyRelated(
          anchorId: 'launch',
          relatedIds: const {'p1'},
          memberId: 'launch',
        ),
        isTrue,
      );
    });

    test('false for an unrelated member (routes to the authorize chain)', () {
      expect(
        isAlreadyRelated(
          anchorId: 'launch',
          relatedIds: const {'p1'},
          memberId: 'stranger',
        ),
        isFalse,
      );
    });
  });
}
