import 'package:equatable/equatable.dart';

import 'package:crm/features/members_list/data/models/date_range_filter.dart';
import 'package:crm/features/members_list/data/models/members_list_filters.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/features/members_list/data/models/members_list_view.dart';

/// Events for the MembersListBloc.
sealed class MembersListEvent extends Equatable {
  const MembersListEvent();

  @override
  List<Object?> get props => [];
}

/// Initial load of the members list and total counts.
class MembersListInitRequested
    extends MembersListEvent {
  final String gymId;

  const MembersListInitRequested(this.gymId);

  @override
  List<Object?> get props => [gymId];
}

/// User tapped a different view button.
class MembersListViewChanged extends MembersListEvent {
  final MembersListView newView;

  const MembersListViewChanged(this.newView);

  @override
  List<Object?> get props => [newView];
}

/// User added a membership status filter.
class MembersListStatusFilterAdded
    extends MembersListEvent {
  final MembershipStatus status;

  const MembersListStatusFilterAdded(this.status);

  @override
  List<Object?> get props => [status];
}

/// User removed a membership status filter.
class MembersListStatusFilterRemoved
    extends MembersListEvent {
  final MembershipStatus status;

  const MembersListStatusFilterRemoved(this.status);

  @override
  List<Object?> get props => [status];
}

/// Scroll reached the 80% threshold — load next page.
class MembersListNextPageRequested
    extends MembersListEvent {
  const MembersListNextPageRequested();
}

/// User set a date range filter.
class MembersListDateRangeFilterSet
    extends MembersListEvent {
  final DateRangeFilter dateRange;

  const MembersListDateRangeFilterSet(this.dateRange);

  @override
  List<Object?> get props => [dateRange];
}

/// User cleared the date range filter.
class MembersListDateRangeFilterCleared
    extends MembersListEvent {
  const MembersListDateRangeFilterCleared();
}

/// User applied all filters at once from the dialog.
class MembersListFiltersApplied
    extends MembersListEvent {
  final MembersListFilters filters;

  const MembersListFiltersApplied(this.filters);

  @override
  List<Object?> get props => [filters];
}

/// Client-side name search changed.
class MembersListSearchChanged extends MembersListEvent {
  final String query;

  const MembersListSearchChanged(this.query);

  @override
  List<Object?> get props => [query];
}
