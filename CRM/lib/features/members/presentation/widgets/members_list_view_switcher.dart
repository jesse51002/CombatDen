import 'package:flutter/material.dart';

import 'package:crm/features/members_list/data/models/members_list_total_counts.dart';
import 'package:crm/features/members_list/data/models/members_list_view.dart';
import 'package:crm/shared/widgets/view_switcher.dart';

/// View-switcher tabs for All / Trial / Frozen / Overdue.
///
/// Wraps [ViewSwitcher] and appends the count from
/// [totalCounts] to each tab label, e.g. "Active (42)".
class MembersListViewSwitcher extends StatelessWidget {
  final MembersListView activeView;
  final MembersListTotalCounts totalCounts;
  final ValueChanged<MembersListView> onViewChanged;

  const MembersListViewSwitcher({
    super.key,
    required this.activeView,
    required this.totalCounts,
    required this.onViewChanged,
  });

  static const List<MembersListView> _views = [
    MembersListView.all,
    MembersListView.trial,
    MembersListView.frozen,
    MembersListView.overdue,
  ];

  String _label(MembersListView view) {
    final count = switch (view) {
      MembersListView.all =>
        totalCounts.active + totalCounts.trial,
      MembersListView.trial => totalCounts.trial,
      MembersListView.frozen => totalCounts.frozen,
      MembersListView.overdue => totalCounts.overdue,
    };
    return '${view.displayLabel} ($count)';
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _views.indexOf(activeView);

    return ViewSwitcher(
      labels: _views.map(_label).toList(),
      selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
      onSelected: (i) => onViewChanged(_views[i]),
    );
  }
}
