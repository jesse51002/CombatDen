import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/members/presentation/dialogs/members_list_filter_dialog.dart';
import 'package:crm/features/members_list/bloc/members_list_bloc.dart';
import 'package:crm/features/members_list/bloc/members_list_event.dart';
import 'package:crm/features/members_list/data/models/date_range_filter.dart';
import 'package:crm/features/members_list/data/models/members_list_filters.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/features/memberships/data/models/main_rank.dart';
import 'package:crm/shared/widgets/filter_bar.dart';

/// Filter bar for the members list: an "Add Filter +" button plus a
/// removable chip per active status / plan / date-range filter (the
/// name search lives in the search box, not here).
///
/// Bound to [MembersListBloc]: opening the dialog dispatches
/// [MembersListFiltersApplied]; removing a chip dispatches the matching
/// remove event.
class MembersListFilterBar extends StatelessWidget {
  final MembersListFilters filters;
  final List<MembershipPlanResponse> plans;
  final List<MainRank> ranks;

  const MembersListFilterBar({
    super.key,
    required this.filters,
    required this.plans,
    required this.ranks,
  });

  @override
  Widget build(BuildContext context) {
    final chips = _buildChips();
    return FilterBar(
      filters: chips,
      onAddFilter: () => _openDialog(context),
      onRemoveFilter: (i) => _removeChip(context, chips[i]),
    );
  }

  List<ActiveFilter> _buildChips() {
    final chips = <ActiveFilter>[
      for (final s in filters.membershipStatus)
        ActiveFilter(
          label: 'Status: ${s.displayLabel}',
          type: 'status',
          value: s,
        ),
      for (final id in filters.planIds)
        ActiveFilter(
          label: 'Plan: ${_planName(id)}',
          type: 'plan',
          value: id,
        ),
      for (final id in filters.rankIds)
        ActiveFilter(
          label: 'Rank: ${_rankName(id)}',
          type: 'rank',
          value: id,
        ),
    ];
    final range = filters.dateRange;
    if (range != null) {
      chips.add(ActiveFilter(
        label: 'Date: ${_rangeLabel(range)}',
        type: 'date',
        value: range,
      ));
    }
    return chips;
  }

  String _planName(String id) {
    for (final p in plans) {
      if (p.planId == id) return p.planName;
    }
    return 'Plan';
  }

  String _rankName(String id) {
    for (final r in ranks) {
      if (r.rankId == id) return r.name;
    }
    return 'Rank';
  }

  String _rangeLabel(DateRangeFilter range) {
    final fmt = DateFormat('MMM d, yyyy');
    final start = range.startDate;
    final end = range.endDate;
    final startLabel =
        start == null ? '…' : fmt.format(DateTime.parse(start));
    final endLabel =
        end == null ? '…' : fmt.format(DateTime.parse(end));
    return '$startLabel — $endLabel';
  }

  Future<void> _openDialog(BuildContext context) async {
    final bloc = context.read<MembersListBloc>();
    final result = await MembersListFilterDialog.show(
      context: context,
      initial: filters,
      plans: plans,
      ranks: ranks,
    );
    if (result == null) return;
    bloc.add(MembersListFiltersApplied(result));
  }

  void _removeChip(BuildContext context, ActiveFilter chip) {
    final bloc = context.read<MembersListBloc>();
    switch (chip.type) {
      case 'status':
        bloc.add(MembersListStatusFilterRemoved(
          chip.value as MembershipStatus,
        ));
      case 'plan':
        bloc.add(MembersListPlanFilterRemoved(
          chip.value as String,
        ));
      case 'rank':
        bloc.add(MembersListRankFilterRemoved(
          chip.value as String,
        ));
      case 'date':
        bloc.add(const MembersListDateRangeFilterCleared());
      default:
        throw ArgumentError('Unknown filter chip type: ${chip.type}');
    }
  }
}
