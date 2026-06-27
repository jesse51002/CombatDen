import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/design_constants.dart';
import 'package:crm/features/members_list/bloc/members_list_bloc.dart';
import 'package:crm/features/members_list/bloc/members_list_event.dart';
import 'package:crm/features/members_list/bloc/members_list_state.dart';
import 'package:crm/features/members/presentation/widgets/members_list_controls.dart';
import 'package:crm/features/members/presentation/widgets/members_list_filter_bar.dart';
import 'package:crm/features/members/presentation/widgets/members_list_header.dart';
import 'package:crm/features/members/presentation/widgets/members_list_table.dart';
import 'package:crm/features/members/presentation/widgets/members_list_view_switcher.dart';

/// Loaded body for the Members screen. Fixed header,
/// view-switcher tabs and search controls sit above an
/// [Expanded] table that fills the remaining height and
/// scrolls internally (the table must have a bounded
/// height — see the build note).
class MembersListBody extends StatelessWidget {
  final MembersListLoaded state;

  const MembersListBody({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    // Fixed header/tabs/controls; the table fills the remaining
    // height (Expanded → bounded) and scrolls internally. The table
    // must NOT sit inside a vertical scroll view — AppDataTable
    // (non-shrinkWrap) sizes to constraints.maxHeight, which is
    // infinite under a SingleChildScrollView and crashes layout.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DesignConstants.spacingBig,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            top: DesignConstants.paddingBig,
            left: DesignConstants.paddingBig,
            right: DesignConstants.paddingBig,
          ),
          child: MembersListHeader(
            totalCounts: state.totalCounts,
          ),
        ),
        MembersListViewSwitcher(
          activeView: state.activeView,
          totalCounts: state.totalCounts,
          onViewChanged: (view) =>
              context.read<MembersListBloc>().add(
                    MembersListViewChanged(view),
                  ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignConstants.paddingBig,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DesignConstants.spacingMedium,
            children: [
              MembersListControls(
                searchQuery: state.searchQuery,
                onSearchChanged: (q) =>
                    context.read<MembersListBloc>().add(
                          MembersListSearchChanged(q),
                        ),
              ),
              MembersListFilterBar(
                filters: state.filters,
                plans: state.plans,
              ),
            ],
          ),
        ),
        Expanded(
          child: MembersListTable(
            activeView: state.activeView,
            rows: state.displayedRows,
            gymId: state.gymId,
            isLoadingMore: state.isLoadingMore,
            hasReachedEnd: state.hasReachedEnd,
            hasActiveFilters:
                state.filters.hasActiveFilters,
            onLoadMore: () =>
                context.read<MembersListBloc>().add(
                      const MembersListNextPageRequested(),
                    ),
          ),
        ),
      ],
    );
  }
}
