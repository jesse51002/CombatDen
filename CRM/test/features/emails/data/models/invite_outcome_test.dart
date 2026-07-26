import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/emails/data/models/invite_outcome.dart';

/// The whole point of this enum is that a confirmation cannot lie about a
/// send. These tests pin that: exactly one value means "sent", and an
/// unrecognised backend value degrades to "we can't confirm", never to
/// success.
void main() {
  test('parses every backend value', () {
    expect(InviteOutcome.fromJson('queued'), InviteOutcome.queued);
    expect(InviteOutcome.fromJson('held'), InviteOutcome.held);
    expect(
      InviteOutcome.fromJson('skipped_no_email'),
      InviteOutcome.skippedNoEmail,
    );
    expect(
      InviteOutcome.fromJson('skipped_suppressed'),
      InviteOutcome.skippedSuppressed,
    );
    expect(
      InviteOutcome.fromJson('not_requested'),
      InviteOutcome.notRequested,
    );
  });

  test('a value this build has never seen falls back, never crashes', () {
    expect(
      InviteOutcome.fromJson('deferred_to_next_tuesday'),
      InviteOutcome.unknown,
    );
  });

  test('ONLY queued counts as sent', () {
    for (final o in InviteOutcome.values) {
      expect(o.wasSent, o == InviteOutcome.queued, reason: '$o');
    }
  });

  test(
    'every not-sent outcome states that nothing went out, and never says '
    '"sent"',
    () {
      for (final o in InviteOutcome.values) {
        if (o == InviteOutcome.queued) {
          expect(o.confirmation, 'Invite sent');
          continue;
        }
        if (o == InviteOutcome.notRequested) {
          // Nobody asked — there is nothing to say about an invite at all.
          expect(o.confirmation, isNull);
          continue;
        }
        final line = o.confirmation!;
        expect(
          line.toLowerCase(),
          isNot(contains('invite sent')),
          reason: '$o must not read as a send',
        );
        expect(line, isNotEmpty);
      }
    },
  );
}
