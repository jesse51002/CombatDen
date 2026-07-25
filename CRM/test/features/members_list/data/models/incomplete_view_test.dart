import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/members_list/data/models/member_row.dart';
import 'package:crm/features/members_list/data/models/members_list_total_counts.dart';
import 'package:crm/features/members_list/data/models/members_list_view.dart';

/// The Incomplete view's wire contract.
///
/// A row here is someone the gym started onboarding who has NOTHING
/// running — no membership of their own, and not the payer on anyone
/// else's. The backend derives that in SQL
/// (`src/members/sql/crm_views/_member_incomplete.sql`); the client's
/// only job is to parse the row shape exactly and to keep working when
/// it is talking to a backend that predates the view.
void main() {
  group('MembersListView.incomplete', () {
    test('round-trips through JSON', () {
      expect(MembersListView.incomplete.value, 'incomplete');
      expect(
        MembersListView.incomplete.toJson(),
        'incomplete',
      );
      expect(
        MembersListView.fromJson('incomplete'),
        MembersListView.incomplete,
      );
    });

    test('carries the tab label the switcher shows', () {
      expect(
        MembersListView.incomplete.displayLabel,
        'Incomplete',
      );
    });

    test(
      'an unrecognised view value still falls back to all, so a '
      'newer backend view cannot blank the screen',
      () {
        expect(
          MembersListView.fromJson('some_future_view'),
          MembersListView.all,
        );
        expect(
          MembersListView.fromJson(''),
          MembersListView.all,
        );
      },
    );
  });

  group('IncompleteViewRow', () {
    // Mirrors `IncompleteViewRow` in
    // FastApiBackend/src/members/schema/members_crm_members_list_schema.py
    // field for field.
    Map<String, dynamic> json() => <String, dynamic>{
          'view': 'incomplete',
          'member_id': 'mem-1',
          'name': 'Dana Reyes',
          'avatar_url': 'https://cdn.combatden.net/member/dana.jpg',
          'email': 'dana@example.com',
          'phone': '+1 555 0100',
          'days_waiting': 3,
        };

    test('parses every field the backend sends', () {
      final row = MemberRow.fromJson(
        json(),
        MembersListView.incomplete,
      );

      expect(row, isA<IncompleteViewRow>());
      final r = row as IncompleteViewRow;
      expect(r.memberId, 'mem-1');
      expect(r.name, 'Dana Reyes');
      expect(
        r.avatarUrl,
        'https://cdn.combatden.net/member/dana.jpg',
      );
      expect(r.email, 'dana@example.com');
      expect(r.phone, '+1 555 0100');
      expect(r.daysWaiting, 3);
    });

    test(
      'a signup that left only one contact detail still parses — '
      'the whole point of the queue is chasing a half-filled row',
      () {
        final partial = json()
          ..remove('email')
          ..remove('phone')
          ..remove('avatar_url');

        final r = MemberRow.fromJson(
          partial,
          MembersListView.incomplete,
        ) as IncompleteViewRow;

        expect(r.email, isNull);
        expect(r.phone, isNull);
        expect(r.avatarUrl, isNull);
        expect(r.daysWaiting, 3);
      },
    );

    test('a same-day signup arrives as zero days waiting', () {
      final r = MemberRow.fromJson(
        json()..['days_waiting'] = 0,
        MembersListView.incomplete,
      ) as IncompleteViewRow;

      expect(r.daysWaiting, 0);
    });
  });

  group('MembersListTotalCounts.incomplete', () {
    test('parses when the backend sends it', () {
      final counts = MembersListTotalCounts.fromJson(const {
        'active': 12,
        'trial': 3,
        'frozen': 1,
        'overdue': 2,
        'dormant': 4,
        'incomplete': 7,
      });

      expect(counts.incomplete, 7);
      expect(counts.dormant, 4);
    });

    test(
      'defaults to 0 when ABSENT, so an older backend cannot break '
      'the members list',
      () {
        final counts = MembersListTotalCounts.fromJson(const {
          'active': 12,
          'trial': 3,
          'frozen': 1,
          'overdue': 2,
        });

        expect(counts.incomplete, 0);
        expect(counts.dormant, 0);
        expect(counts.active, 12);
      },
    );

    test('an explicit null also lands on 0, never a crash', () {
      final counts = MembersListTotalCounts.fromJson(const {
        'active': 0,
        'trial': 0,
        'frozen': 0,
        'overdue': 0,
        'dormant': null,
        'incomplete': null,
      });

      expect(counts.incomplete, 0);
      expect(counts.dormant, 0);
    });

    test('the count takes part in equality', () {
      const a = MembersListTotalCounts(
        active: 1,
        trial: 0,
        frozen: 0,
        overdue: 0,
        incomplete: 2,
      );
      const b = MembersListTotalCounts(
        active: 1,
        trial: 0,
        frozen: 0,
        overdue: 0,
        incomplete: 5,
      );

      expect(a, isNot(b));
    });
  });
}
