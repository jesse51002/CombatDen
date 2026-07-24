import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:crm/features/members_list/data/models/members_list_view.dart';
import 'package:crm/shared/widgets/empty_state.dart';

/// What the members table shows when a view returns no rows.
///
/// With a filter active, zero rows means "nothing matched" — point at
/// the filters. Otherwise it is a genuinely empty view.
class MembersTableEmptyState extends StatelessWidget {
  final MembersListView activeView;
  final bool hasActiveFilters;

  const MembersTableEmptyState({
    super.key,
    required this.activeView,
    required this.hasActiveFilters,
  });

  @override
  Widget build(BuildContext context) {
    if (hasActiveFilters) {
      return const EmptyState(
        icon: Symbols.people_sharp,
        title: 'No members match your filters',
        body: 'Try removing filters to see more.',
      );
    }

    // Incomplete is the one view where an empty list is GOOD NEWS —
    // nobody is stranded part-way through joining — so it gets an
    // affirmative icon and copy instead of a flat "none found".
    return switch (activeView) {
      MembersListView.incomplete => const EmptyState(
          icon: Symbols.task_alt_sharp,
          title: 'Every signup is finished',
          body: 'Nobody is stuck part-way through joining. '
              'Anyone who starts at the kiosk and stops before '
              'paying shows up here so you can finish it for them.',
        ),
      MembersListView.all => const EmptyState(
          icon: Symbols.people_sharp,
          title: 'No members yet',
        ),
      MembersListView.trial => const EmptyState(
          icon: Symbols.people_sharp,
          title: 'No trial members',
        ),
      MembersListView.frozen => const EmptyState(
          icon: Symbols.people_sharp,
          title: 'No frozen members',
        ),
      MembersListView.overdue => const EmptyState(
          icon: Symbols.people_sharp,
          title: 'No overdue members',
        ),
    };
  }
}
