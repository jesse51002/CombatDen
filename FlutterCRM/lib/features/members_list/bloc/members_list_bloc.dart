import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/app_constants.dart';
import 'package:crm/features/members_list/bloc/members_list_event.dart';
import 'package:crm/features/members_list/bloc/members_list_state.dart';
import 'package:crm/features/members_list/data/models/crm_members_list_request.dart';
import 'package:crm/features/members_list/data/models/crm_members_list_response.dart';
import 'package:crm/features/members_list/data/models/member_row.dart';
import 'package:crm/features/members_list/data/models/members_list_total_counts.dart';
import 'package:crm/features/members_list/data/models/members_list_filters.dart';
import 'package:crm/features/members_list/data/models/members_list_view.dart';
import 'package:crm/features/members_list/data/models/membership_status.dart';
import 'package:crm/features/members_list/data/repositories/members_list_repository.dart';

/// BLoC for the Members List screen.
///
/// Manages view switching, filtering, pagination,
/// and client-side search.
class MembersListBloc
    extends Bloc<MembersListEvent, MembersListState> {
  final MembersListRepository _repository;

  MembersListBloc({
    required MembersListRepository repository,
  })  : _repository = repository,
        super(const MembersListInitial()) {
    on<MembersListInitRequested>(_onInitRequested);
    on<MembersListViewChanged>(_onViewChanged);
    on<MembersListStatusFilterAdded>(
      _onStatusFilterAdded,
    );
    on<MembersListStatusFilterRemoved>(
      _onStatusFilterRemoved,
    );
    on<MembersListDateRangeFilterSet>(
      _onDateRangeFilterSet,
    );
    on<MembersListDateRangeFilterCleared>(
      _onDateRangeFilterCleared,
    );
    on<MembersListFiltersApplied>(_onFiltersApplied);
    on<MembersListNextPageRequested>(
      _onNextPageRequested,
    );
    on<MembersListSearchChanged>(_onSearchChanged);
  }

  Future<void> _onInitRequested(
    MembersListInitRequested event,
    Emitter<MembersListState> emit,
  ) async {
    emit(const MembersListLoading());

    try {
      final request = CrmMembersListRequest(
        gymId: event.gymId,
        prevView: MembersListView.all,
        requestedView: MembersListView.all,
      );

      final results = await Future.wait([
        _repository.getMembersList(request),
        _repository.getTotalCounts(event.gymId),
      ]);

      final listResponse =
          results[0] as CrmMembersListResponse;
      final totalCounts =
          results[1] as MembersListTotalCounts;

      emit(MembersListLoaded(
        gymId: event.gymId,
        activeView: MembersListView.all,
        prevView: MembersListView.all,
        filters: listResponse.filters,
        allRows: List<MemberRow>.from(
          listResponse.data,
        ),
        displayedRows: List<MemberRow>.from(
          listResponse.data,
        ),
        totalCounts: totalCounts,
        hasReachedEnd: listResponse.data.length <
            AppConstants.defaultPageSize,
      ));
    } catch (e, stackTrace) {
      log(
        'Failed to load members list',
        error: e,
        stackTrace: stackTrace,
      );
      emit(MembersListError(
        e.toString(),
        gymId: event.gymId,
      ));
    }
  }

  Future<void> _onViewChanged(
    MembersListViewChanged event,
    Emitter<MembersListState> emit,
  ) async {
    final currentState = state;
    if (currentState is! MembersListLoaded) return;
    if (currentState.activeView == event.newView) return;

    // Keep date filters, reset membership_status
    final newFilters = currentState.filters.copyWith(
      membershipStatus: const [],
    );

    await _fetchFreshPage(
      emit: emit,
      gymId: currentState.gymId,
      prevView: currentState.activeView,
      requestedView: event.newView,
      filters: newFilters,
      totalCounts: currentState.totalCounts,
    );
  }

  Future<void> _onStatusFilterAdded(
    MembersListStatusFilterAdded event,
    Emitter<MembersListState> emit,
  ) async {
    final currentState = state;
    if (currentState is! MembersListLoaded) return;

    final newStatuses = [
      ...currentState.filters.membershipStatus,
      event.status,
    ];

    final newFilters = currentState.filters.copyWith(
      membershipStatus: newStatuses,
    );

    // Smart view switching: exactly 1 status → switch
    final targetView = _resolveView(newStatuses);

    await _fetchFreshPage(
      emit: emit,
      gymId: currentState.gymId,
      prevView: currentState.activeView,
      requestedView: targetView,
      filters: newFilters,
      totalCounts: currentState.totalCounts,
    );
  }

  Future<void> _onStatusFilterRemoved(
    MembersListStatusFilterRemoved event,
    Emitter<MembersListState> emit,
  ) async {
    final currentState = state;
    if (currentState is! MembersListLoaded) return;

    final newStatuses = currentState
        .filters.membershipStatus
        .where((s) => s != event.status)
        .toList();

    final newFilters = currentState.filters.copyWith(
      membershipStatus: newStatuses,
    );

    final targetView = _resolveView(newStatuses);

    await _fetchFreshPage(
      emit: emit,
      gymId: currentState.gymId,
      prevView: currentState.activeView,
      requestedView: targetView,
      filters: newFilters,
      totalCounts: currentState.totalCounts,
    );
  }

  Future<void> _onDateRangeFilterSet(
    MembersListDateRangeFilterSet event,
    Emitter<MembersListState> emit,
  ) async {
    final currentState = state;
    if (currentState is! MembersListLoaded) return;

    final newFilters = currentState.filters.copyWith(
      dateRange: event.dateRange,
    );

    await _fetchFreshPage(
      emit: emit,
      gymId: currentState.gymId,
      prevView: currentState.activeView,
      requestedView: currentState.activeView,
      filters: newFilters,
      totalCounts: currentState.totalCounts,
    );
  }

  Future<void> _onFiltersApplied(
    MembersListFiltersApplied event,
    Emitter<MembersListState> emit,
  ) async {
    final currentState = state;
    if (currentState is! MembersListLoaded) return;

    final targetView = _resolveView(
      event.filters.membershipStatus,
    );

    await _fetchFreshPage(
      emit: emit,
      gymId: currentState.gymId,
      prevView: currentState.activeView,
      requestedView: targetView,
      filters: event.filters,
      totalCounts: currentState.totalCounts,
    );
  }

  Future<void> _onDateRangeFilterCleared(
    MembersListDateRangeFilterCleared event,
    Emitter<MembersListState> emit,
  ) async {
    final currentState = state;
    if (currentState is! MembersListLoaded) return;

    final newFilters = currentState.filters.copyWith(
      clearDateRange: true,
    );

    await _fetchFreshPage(
      emit: emit,
      gymId: currentState.gymId,
      prevView: currentState.activeView,
      requestedView: currentState.activeView,
      filters: newFilters,
      totalCounts: currentState.totalCounts,
    );
  }

  Future<void> _onNextPageRequested(
    MembersListNextPageRequested event,
    Emitter<MembersListState> emit,
  ) async {
    final currentState = state;
    if (currentState is! MembersListLoaded) return;
    if (currentState.isLoadingMore) return;
    if (currentState.hasReachedEnd) return;

    final nextIndex = currentState.startIndex +
        AppConstants.defaultPageSize;

    emit(currentState.copyWith(isLoadingMore: true));

    try {
      final request = CrmMembersListRequest(
        gymId: currentState.gymId,
        prevView: currentState.activeView,
        requestedView: currentState.activeView,
        filters: currentState.filters,
        startIndex: nextIndex,
      );

      final response =
          await _repository.getMembersList(request);

      // Discard stale response if view changed
      final afterState = state;
      if (afterState is! MembersListLoaded ||
          afterState.activeView !=
              currentState.activeView) {
        return;
      }

      final allRows = [
        ...currentState.allRows,
        ...response.data,
      ];

      emit(currentState.copyWith(
        allRows: allRows,
        displayedRows: _applySearch(
          allRows,
          currentState.searchQuery,
        ),
        startIndex: nextIndex,
        hasReachedEnd: response.data.length <
            AppConstants.defaultPageSize,
        isLoadingMore: false,
      ));
    } catch (e, stackTrace) {
      log(
        'Failed to load next page',
        error: e,
        stackTrace: stackTrace,
      );
      // Revert loading state but stay on loaded
      final afterState = state;
      if (afterState is MembersListLoaded) {
        emit(afterState.copyWith(isLoadingMore: false));
      }
    }
  }

  void _onSearchChanged(
    MembersListSearchChanged event,
    Emitter<MembersListState> emit,
  ) {
    final currentState = state;
    if (currentState is! MembersListLoaded) return;

    emit(currentState.copyWith(
      searchQuery: event.query,
      displayedRows: _applySearch(
        currentState.allRows,
        event.query,
      ),
    ));
  }

  /// Fetches a fresh first page after view/filter
  /// change. Resets pagination.
  Future<void> _fetchFreshPage({
    required Emitter<MembersListState> emit,
    required String gymId,
    required MembersListView prevView,
    required MembersListView requestedView,
    required MembersListFilters filters,
    required dynamic totalCounts,
  }) async {
    emit(const MembersListLoading());

    try {
      final request = CrmMembersListRequest(
        gymId: gymId,
        prevView: prevView,
        requestedView: requestedView,
        filters: filters,
      );

      final response =
          await _repository.getMembersList(request);

      final rows =
          List<MemberRow>.from(response.data);

      emit(MembersListLoaded(
        gymId: gymId,
        activeView: requestedView,
        prevView: prevView,
        filters: response.filters,
        allRows: rows,
        displayedRows: rows,
        totalCounts: totalCounts,
        hasReachedEnd: response.data.length <
            AppConstants.defaultPageSize,
      ));
    } catch (e, stackTrace) {
      log(
        'Failed to load members list',
        error: e,
        stackTrace: stackTrace,
      );
      emit(MembersListError(
        e.toString(),
        gymId: gymId,
      ));
    }
  }

  /// Resolves the target view based on the number of
  /// active membership status filters.
  MembersListView _resolveView(
    List<MembershipStatus> statuses,
  ) {
    if (statuses.length != 1) {
      return MembersListView.all;
    }

    return switch (statuses.first) {
      MembershipStatus.trial => MembersListView.trial,
      MembershipStatus.frozen => MembersListView.frozen,
      MembershipStatus.overdue =>
        MembersListView.overdue,
      _ => MembersListView.all,
    };
  }

  /// Filters rows by name (client-side).
  List<MemberRow> _applySearch(
    List<MemberRow> rows,
    String query,
  ) {
    final trimmed = query.toLowerCase().trim();
    if (trimmed.isEmpty) return rows;

    return rows
        .where(
          (r) => r.name.toLowerCase().contains(trimmed),
        )
        .toList();
  }
}
