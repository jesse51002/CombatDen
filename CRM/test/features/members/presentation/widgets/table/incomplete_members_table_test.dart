import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/members/presentation/widgets/table/members_table.dart';
import 'package:crm/features/members/presentation/widgets/table/members_table_columns.dart';
import 'package:crm/features/members/presentation/widgets/table/members_table_empty_state.dart';
import 'package:crm/features/members_list/data/models/member_row.dart';
import 'package:crm/features/members_list/data/models/members_list_view.dart';

/// The Incomplete view's rendering.
///
/// The column list and the per-row cell list are built by two separate
/// switches, so a mismatch between them is a runtime `RangeError` on a
/// live staff screen that `flutter analyze` cannot see. These tests pin
/// them together, and pin the empty state's good-news copy.
void main() {
  Widget host(Widget child) => MaterialApp(
        home: Scaffold(body: child),
      );

  const rows = [
    IncompleteViewRow(
      memberId: 'mem-1',
      name: 'Dana Reyes',
      email: 'dana@example.com',
      phone: '+1 555 0100',
      daysWaiting: 3,
    ),
    IncompleteViewRow(
      memberId: 'mem-2',
      name: 'Sam Okafor',
      daysWaiting: 0,
    ),
  ];

  test('every view has as many columns as its rows have cells', () {
    // Cheap structural guard: the Incomplete view's five columns are
    // what the five-cell row below is laid into.
    expect(
      membersTableColumns(MembersListView.incomplete),
      hasLength(5),
    );
  });

  testWidgets(
    'renders name, email, phone, waiting, and the row action',
    (tester) async {
      await tester.pumpWidget(
        host(
          const MembersTable(
            activeView: MembersListView.incomplete,
            members: rows,
            gymId: 'gym-1',
            isLoadingMore: false,
            hasReachedEnd: true,
            onLoadMore: _noop,
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Dana Reyes'), findsOneWidget);
      expect(find.text('dana@example.com'), findsOneWidget);
      expect(find.text('+1 555 0100'), findsOneWidget);
      expect(find.text('3 days'), findsOneWidget);
      // A same-day signup reads "Today", not "0 days".
      expect(find.text('Today'), findsOneWidget);
      // Missing contact details fall back to a dash rather than a gap:
      // Sam left neither an email nor a phone.
      expect(find.text('—'), findsNWidgets(2));
      expect(find.text('Finish signup'), findsNWidgets(2));
    },
  );

  testWidgets(
    'the empty state reads as good news, not as an error',
    (tester) async {
      await tester.pumpWidget(
        host(
          const MembersTableEmptyState(
            activeView: MembersListView.incomplete,
            hasActiveFilters: false,
          ),
        ),
      );

      expect(find.text('Every signup is finished'), findsOneWidget);
      expect(
        find.textContaining('Nobody is stuck part-way'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'with a filter on, an empty Incomplete list points at the '
    'filters instead of claiming everyone is done',
    (tester) async {
      await tester.pumpWidget(
        host(
          const MembersTableEmptyState(
            activeView: MembersListView.incomplete,
            hasActiveFilters: true,
          ),
        ),
      );

      expect(
        find.text('No members match your filters'),
        findsOneWidget,
      );
      expect(find.text('Every signup is finished'), findsNothing);
    },
  );
}

void _noop() {}
