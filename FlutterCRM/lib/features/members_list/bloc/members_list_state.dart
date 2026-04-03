import 'package:equatable/equatable.dart';

import 'package:crm/features/members_list/data/models/member_row.dart';
import 'package:crm/features/members_list/data/models/members_list_filters.dart';
import 'package:crm/features/members_list/data/models/members_list_total_counts.dart';
import 'package:crm/features/members_list/data/models/members_list_view.dart';

/// States for the MembersListBloc.
sealed class MembersListState extends Equatable {
  const MembersListState();

  @override
  List<Object?> get props => [];
}

/// Initial state before any data is loaded.
class MembersListInitial extends MembersListState {
  const MembersListInitial();
}

/// Loading state while fetching the first page.
class MembersListLoading extends MembersListState {
  const MembersListLoading();
}

/// Successfully loaded members list data.
class MembersListLoaded extends MembersListState {
  /// The gym ID for this list.
  final String gymId;

  /// The currently active view.
  final MembersListView activeView;

  /// The previously active view (for API prev_view).
  final MembersListView prevView;

  /// Active filters.
  final MembersListFilters filters;

  /// All rows loaded so far (across pages).
  final List<MemberRow> allRows;

  /// Rows after client-side search filtering.
  final List<MemberRow> displayedRows;

  /// Current search query.
  final String searchQuery;

  /// Total member counts (unfiltered).
  final MembersListTotalCounts totalCounts;

  /// Current pagination offset.
  final int startIndex;

  /// Whether there are no more pages to load.
  final bool hasReachedEnd;

  /// Whether a next-page request is in progress.
  final bool isLoadingMore;

  const MembersListLoaded({
    required this.gymId,
    required this.activeView,
    required this.prevView,
    required this.filters,
    required this.allRows,
    required this.displayedRows,
    this.searchQuery = '',
    required this.totalCounts,
    this.startIndex = 0,
    this.hasReachedEnd = false,
    this.isLoadingMore = false,
  });

  MembersListLoaded copyWith({
    String? gymId,
    MembersListView? activeView,
    MembersListView? prevView,
    MembersListFilters? filters,
    List<MemberRow>? allRows,
    List<MemberRow>? displayedRows,
    String? searchQuery,
    MembersListTotalCounts? totalCounts,
    int? startIndex,
    bool? hasReachedEnd,
    bool? isLoadingMore,
  }) {
    return MembersListLoaded(
      gymId: gymId ?? this.gymId,
      activeView: activeView ?? this.activeView,
      prevView: prevView ?? this.prevView,
      filters: filters ?? this.filters,
      allRows: allRows ?? this.allRows,
      displayedRows:
          displayedRows ?? this.displayedRows,
      searchQuery: searchQuery ?? this.searchQuery,
      totalCounts: totalCounts ?? this.totalCounts,
      startIndex: startIndex ?? this.startIndex,
      hasReachedEnd:
          hasReachedEnd ?? this.hasReachedEnd,
      isLoadingMore:
          isLoadingMore ?? this.isLoadingMore,
    );
  }

  @override
  List<Object?> get props => [
        gymId,
        activeView,
        prevView,
        filters,
        allRows,
        displayedRows,
        searchQuery,
        totalCounts,
        startIndex,
        hasReachedEnd,
        isLoadingMore,
      ];
}

/// Error state when loading fails.
class MembersListError extends MembersListState {
  final String message;
  final String gymId;

  const MembersListError(this.message, {required this.gymId});

  @override
  List<Object?> get props => [message, gymId];
}
