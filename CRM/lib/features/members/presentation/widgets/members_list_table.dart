import 'package:flutter/material.dart';

import 'package:crm/features/members/presentation/widgets/table/members_table.dart';
import 'package:crm/features/members_list/data/models/member_row.dart';
import 'package:crm/features/members_list/data/models/members_list_view.dart';

/// Thin wrapper that passes the bloc's [rows], [gymId],
/// [activeView], and pagination flags down to [MembersTable].
///
/// Kept separate so [MembersListBody] stays clean.
class MembersListTable extends StatelessWidget {
  final MembersListView activeView;
  final List<MemberRow> rows;
  final String gymId;
  final bool isLoadingMore;
  final bool hasReachedEnd;
  final VoidCallback onLoadMore;
  final bool hasActiveFilters;

  const MembersListTable({
    super.key,
    required this.activeView,
    required this.rows,
    required this.gymId,
    required this.isLoadingMore,
    required this.hasReachedEnd,
    required this.onLoadMore,
    this.hasActiveFilters = false,
  });

  @override
  Widget build(BuildContext context) {
    return MembersTable(
      activeView: activeView,
      members: rows,
      gymId: gymId,
      isLoadingMore: isLoadingMore,
      hasReachedEnd: hasReachedEnd,
      onLoadMore: onLoadMore,
      hasActiveFilters: hasActiveFilters,
    );
  }
}
