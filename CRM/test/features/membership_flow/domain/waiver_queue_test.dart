import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/membership_flow/domain/waiver_queue.dart';

/// **The already-signed skip fails CLOSED, and that is a legal invariant.**
///
/// A needless signature costs the member twenty seconds. A MISSING one voids
/// the gym's protection. So a waiver only ever leaves the queue on a positive
/// server verdict that the person's existing signature is at or above the
/// re-sign floor — an absent, failed or unread answer means ASK.
///
/// The one thing the skip may never remove is a waiver the SERVER named at a
/// 422 gate: that gate is the backstop that makes a client-side skip safe at
/// all, and dropping one loops the member through a run that never satisfies it.
void main() {
  group('waiverQueueFor', () {
    test('every plan waiver is asked for when nothing is satisfied', () {
      expect(
        waiverQueueFor(
          planWaiverIds: const ['liability', 'media'],
          serverGatedWaiverIds: const {},
          satisfiedWaiverIds: const {},
        ),
        ['liability', 'media'],
      );
    });

    test('a satisfied waiver is DROPPED, not stepped over', () {
      // The queue is the "waiver 2 of 3" numbering, so it must count the
      // signatures the member is about to give — not the ones the gym holds.
      expect(
        waiverQueueFor(
          planWaiverIds: const ['liability', 'media'],
          serverGatedWaiverIds: const {},
          satisfiedWaiverIds: const {'liability'},
        ),
        ['media'],
      );
    });

    test('a SERVER-gated waiver survives the satisfied skip', () {
      // The 422 is authoritative: if the gate names it, the member signs it,
      // whatever a prior read said.
      expect(
        waiverQueueFor(
          planWaiverIds: const ['liability'],
          serverGatedWaiverIds: const {'liability'},
          satisfiedWaiverIds: const {'liability'},
        ),
        ['liability'],
      );
    });

    test('a gated waiver the plan does not list is appended', () {
      // A plan whose waiver list drifted from the gate would otherwise loop
      // the member forever.
      expect(
        waiverQueueFor(
          planWaiverIds: const ['liability'],
          serverGatedWaiverIds: const {'house-rules'},
          satisfiedWaiverIds: const {},
        ),
        ['liability', 'house-rules'],
      );
    });

    test('a gated waiver already in the queue is not duplicated', () {
      expect(
        waiverQueueFor(
          planWaiverIds: const ['liability', 'media'],
          serverGatedWaiverIds: const {'media'},
          satisfiedWaiverIds: const {},
        ),
        ['liability', 'media'],
      );
    });

    test('blank plan entries never become a waiver to sign', () {
      expect(
        waiverQueueFor(
          planWaiverIds: const ['', '   ', 'liability'],
          serverGatedWaiverIds: const {},
          satisfiedWaiverIds: const {},
        ),
        ['liability'],
      );
    });

    test('a plan with no waivers owes nothing', () {
      expect(
        waiverQueueFor(
          planWaiverIds: const [],
          serverGatedWaiverIds: const {},
          satisfiedWaiverIds: const {'liability'},
        ),
        isEmpty,
      );
    });
  });

  group('firstUnsignedIndex', () {
    test('opens at the first entry still owed', () {
      expect(
        firstUnsignedIndex(
          const ['liability', 'media', 'house-rules'],
          const {'liability'},
        ),
        1,
      );
    });

    test('signed stays signed — Back then forward never re-asks', () {
      expect(
        firstUnsignedIndex(
          const ['liability', 'media'],
          const {'liability', 'media'},
        ),
        isNull,
      );
    });

    test('an empty queue is null, so the person is skipped entirely', () {
      expect(firstUnsignedIndex(const [], const {}), isNull);
    });
  });
}
