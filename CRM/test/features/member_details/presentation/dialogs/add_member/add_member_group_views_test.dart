import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/member_details/presentation/dialogs/add_member/add_member_roster_view.dart';
import 'package:crm/features/member_details/presentation/dialogs/add_member/choose_payer_view.dart';
import 'package:crm/features/member_details/presentation/dialogs/add_member/group_member.dart';
import 'package:crm/features/member_details/presentation/dialogs/add_member/payer_radio_tile.dart';
import 'package:crm/shared/widgets/existing_member_pill.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  const alice = GroupMember(
    memberId: 'a',
    fullName: 'Alice Ray',
    email: 'alice@example.com',
    wasExisting: false,
  );
  const bob = GroupMember(
    memberId: 'b',
    fullName: 'Bob Kim',
    email: 'bob@example.com',
    wasExisting: true,
  );
  const cara = GroupMember(
    memberId: 'c',
    fullName: 'Cara Ng',
    wasExisting: false,
  );

  group('AddMemberRosterView', () {
    testWidgets('one new member reads as an added confirmation', (t) async {
      await t.pumpWidget(wrap(AddMemberRosterView(
        group: const [alice],
        onAddAnother: () {},
      )));

      expect(find.text('Alice Ray has been added'), findsOneWidget);
      // The just-added (last) row flashes "Added".
      expect(find.text('Added'), findsOneWidget);
      expect(find.text('Add another person'), findsOneWidget);
    });

    testWidgets('one existing member reads as already a member', (t) async {
      await t.pumpWidget(wrap(AddMemberRosterView(
        group: const [bob],
        onAddAnother: () {},
      )));

      expect(find.text('Bob Kim is already a member'), findsOneWidget);
      expect(find.byType(ExistingMemberPill), findsOneWidget);
    });

    testWidgets('two or more reads as a group; only the last flashes Added',
        (t) async {
      await t.pumpWidget(wrap(AddMemberRosterView(
        group: const [alice, bob, cara],
        onAddAnother: () {},
      )));

      expect(find.text('3 people in this group'), findsOneWidget);
      // Existing member (Bob) still carries the pill.
      expect(find.byType(ExistingMemberPill), findsOneWidget);
      // Only the last-added row (Cara) flashes "Added".
      expect(find.text('Added'), findsOneWidget);
    });

    testWidgets('the adder tile fires onAddAnother', (t) async {
      var tapped = false;
      await t.pumpWidget(wrap(AddMemberRosterView(
        group: const [alice],
        onAddAnother: () => tapped = true,
      )));

      await t.tap(find.text('Add another person'));
      expect(tapped, isTrue);
    });
  });

  group('ChoosePayerView', () {
    testWidgets('tapping a tile fires onSelect with its member id',
        (t) async {
      String? picked;
      await t.pumpWidget(wrap(ChoosePayerView(
        group: const [alice, bob],
        selectedPayerId: null,
        onSelect: (id) => picked = id,
      )));

      expect(find.byType(PayerRadioTile), findsNWidgets(2));
      await t.tap(find.text('Bob Kim'));
      expect(picked, 'b');
    });

    testWidgets('helper pluralizes: 1 authorization for a pair', (t) async {
      await t.pumpWidget(wrap(ChoosePayerView(
        group: const [alice, bob],
        selectedPayerId: 'a',
        onSelect: (_) {},
      )));

      expect(
        find.text('Alice will sign 1 authorization, one for each '
            'other person.'),
        findsOneWidget,
      );
    });

    testWidgets('helper pluralizes: 2 authorizations for a trio', (t) async {
      await t.pumpWidget(wrap(ChoosePayerView(
        group: const [alice, bob, cara],
        selectedPayerId: 'a',
        onSelect: (_) {},
      )));

      expect(
        find.text('Alice will sign 2 authorizations, one for each '
            'other person.'),
        findsOneWidget,
      );
    });

    testWidgets('no helper line until a payer is picked', (t) async {
      await t.pumpWidget(wrap(ChoosePayerView(
        group: const [alice, bob],
        selectedPayerId: null,
        onSelect: (_) {},
      )));

      expect(find.textContaining('will sign'), findsNothing);
    });
  });
}
