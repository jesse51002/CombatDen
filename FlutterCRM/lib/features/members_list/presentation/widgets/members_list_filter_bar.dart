import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import 'package:crm/features/members_list/bloc/members_list_bloc.dart';
import 'package:crm/features/members_list/bloc/members_list_event.dart';
import 'package:crm/features/members_list/bloc/members_list_state.dart';
import 'package:crm/features/members_list/data/models/date_range_filter.dart';
import 'package:crm/features/members_list/data/models/members_list_filters.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/features/members_list/presentation/widgets/members_list_filter_dialog.dart';
import 'package:crm/shared/widgets/filter_bar.dart';

/// Filter bar for the members list screen.
///
/// Displays active filter chips and opens the filter
/// dialog when "Add Filter +" is tapped.
class MembersListFilterBar extends StatelessWidget {
  const MembersListFilterBar({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MembersListBloc,
        MembersListState>(
      builder: (context, state) {
        if (state is! MembersListLoaded) {
          return const SizedBox.shrink();
        }

        final filters = _buildActiveFilters(
          state.filters,
        );

        return FilterBar(
          filters: filters,
          onAddFilter: () => _openFilterDialog(
            context,
            state,
          ),
          onRemoveFilter: (index) =>
              _removeFilter(context, filters[index]),
        );
      },
    );
  }

  List<ActiveFilter> _buildActiveFilters(
    MembersListFilters filters,
  ) {
    final active = <ActiveFilter>[];

    for (final status in filters.membershipStatus) {
      active.add(ActiveFilter(
        label: 'Status: ${status.displayLabel}',
        type: 'membership_status',
        value: status,
      ));
    }

    if (filters.dateRange != null) {
      final dr = filters.dateRange!;
      final formatter = DateFormat('MMM d, yyyy');
      final start = dr.startDate != null
          ? formatter.format(
              DateTime.parse(dr.startDate!),
            )
          : '...';
      final end = dr.endDate != null
          ? formatter.format(
              DateTime.parse(dr.endDate!),
            )
          : '...';
      active.add(ActiveFilter(
        label: 'Date: $start — $end',
        type: 'date_range',
        value: filters.dateRange,
      ));
    }

    return active;
  }

  Future<void> _openFilterDialog(
    BuildContext context,
    MembersListLoaded state,
  ) async {
    final result =
        await showDialog<FilterDialogResult>(
      context: context,
      builder: (_) => MembersListFilterDialog(
        currentFilters: state.filters,
      ),
    );

    if (result == null) return;
    if (!context.mounted) return;

    _applyFilterResult(context, state, result);
  }

  void _removeFilter(
    BuildContext context,
    ActiveFilter filter,
  ) {
    final bloc = context.read<MembersListBloc>();

    if (filter.type == 'membership_status') {
      bloc.add(MembersListStatusFilterRemoved(
        filter.value as MembershipStatus,
      ));
    } else if (filter.type == 'date_range') {
      bloc.add(
        const MembersListDateRangeFilterCleared(),
      );
    }
  }

  void _applyFilterResult(
    BuildContext context,
    MembersListLoaded state,
    FilterDialogResult result,
  ) {
    DateRangeFilter? dateRange = result.dateRange;

    final newFilters = state.filters.copyWith(
      membershipStatus: result.statuses,
      dateRange: dateRange,
      clearDateRange: dateRange == null,
    );

    context.read<MembersListBloc>().add(
          MembersListFiltersApplied(newFilters),
        );
  }
}
