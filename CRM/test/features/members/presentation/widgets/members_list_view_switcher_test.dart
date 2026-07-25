import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crm/features/members/presentation/widgets/members_list_view_switcher.dart';
import 'package:crm/features/members_list/data/models/members_list_total_counts.dart';
import 'package:crm/features/members_list/data/models/members_list_view.dart';

/// The view switcher carries the Incomplete tab and its count, and
/// selecting it reports the right view back to the bloc.
void main() {
  const counts = MembersListTotalCounts(
    active: 10,
    trial: 4,
    frozen: 1,
    overdue: 2,
    dormant: 3,
    incomplete: 6,
  );

  Widget host({
    required MembersListView active,
    required ValueChanged<MembersListView> onChanged,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: MembersListViewSwitcher(
            activeView: active,
            totalCounts: counts,
            onViewChanged: onChanged,
          ),
        ),
      );

  testWidgets('shows the Incomplete tab with its count', (tester) async {
    await tester.pumpWidget(
      host(
        active: MembersListView.all,
        onChanged: (_) {},
      ),
    );

    expect(find.text('Incomplete (6)'), findsOneWidget);
    // Sits beside the existing tabs, it does not replace one.
    expect(find.text('All (14)'), findsOneWidget);
    expect(find.text('Overdue (2)'), findsOneWidget);
  });

  testWidgets('tapping it reports the incomplete view', (tester) async {
    MembersListView? picked;
    await tester.pumpWidget(
      host(
        active: MembersListView.all,
        onChanged: (v) => picked = v,
      ),
    );

    await tester.tap(find.text('Incomplete (6)'));
    await tester.pump();

    expect(picked, MembersListView.incomplete);
  });

  testWidgets(
    'a gym with nobody mid-signup still shows the tab at (0) — a '
    'silent tab would hide the queue the moment it empties',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MembersListViewSwitcher(
              activeView: MembersListView.incomplete,
              totalCounts: const MembersListTotalCounts(
                active: 1,
                trial: 0,
                frozen: 0,
                overdue: 0,
              ),
              onViewChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Incomplete (0)'), findsOneWidget);
    },
  );
}
