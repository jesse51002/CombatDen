import 'dart:async';
import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:stream_transform/stream_transform.dart';

import 'package:crm/core/constants/app_constants.dart';
import 'package:crm/features/member_details/data/models/membership_plan_response.dart';
import 'package:crm/features/members_list/bloc/members_list_event.dart';
import 'package:crm/features/members_list/bloc/members_list_state.dart';
import 'package:crm/features/members_list/data/models/crm_members_list_request.dart';
import 'package:crm/features/members_list/data/models/crm_members_list_response.dart';
import 'package:crm/features/members_list/data/models/member_row.dart';
import 'package:crm/features/members_list/data/models/members_list_filters.dart';
import 'package:crm/features/members_list/data/models/members_list_total_counts.dart';
import 'package:crm/features/members_list/data/models/members_list_view.dart';
import 'package:crm/features/members_list/data/repositories/members_list_repository.dart';
import 'package:crm/features/memberships/data/models/main_rank.dart';
import 'package:crm/features/memberships/data/repositories/memberships_repository.dart';
import 'package:crm/features/memberships/data/repositories/ranks_repository.dart';

EventTransformer<E> _debounce<E>(Duration duration) {
  return (events, mapper) =>
      events.debounce(duration).switchMap(mapper);
}

/// BLoC for the Members List screen.
///
/// Manages view switching, filtering, pagination, and
/// server-side search. The view and the filters are
/// independent: switching a view tab keeps the active
/// filters, and changing a filter never moves the view.
class MembersListBloc
    extends Bloc<MembersListEvent, MembersListState> {
  final MembersListRepository _repository;
  final MembershipsRepository _membershipsRepository;
  final RanksRepository _ranksRepository;

  int _searchSeq = 0;

  MembersListBloc({
    required MembersListRepository repository,
    required MembershipsRepository membershipsRepository,
    required RanksRepository ranksRepository,
  })  : _repository = repository,
        _membershipsRepository = membershipsRepository,
        _ranksRepository = ranksRepository,
        super(const MembersListInitial()) {
    on<MembersListInitRequested>(_onInitRequested);
    on<MembersListViewChanged>(_onViewChanged);
    on<MembersListStatusFilterAdded>(
      _onStatusFilterAdded,
    );
    on<MembersListStatusFilterRemoved>(
      _onStatusFilterRemoved,
    );
    on<MembersListPlanFilterRemoved>(
      _onPlanFilterRemoved,
    );
    on<MembersListRankFilterRemoved>(
      _onRankFilterRemoved,
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
    on<MembersListSearchChanged>(
      _onSearchChanged,
      transformer: _debounce(
        const Duration(milliseconds: 300),
      ),
    );
  }

  Future<void> _onInitRequested(
    MembersListInitRequested event,
    Emitter<MembersListState> emit,
  ) async {
    emit(const MembersListLoading());

    try {
      final request = CrmMembersListRequest(
        gymId: event.gymId,
        view: MembersListView.all,
      );

      // Plans + ranks back the filter picker; their loads are
      // best-effort and must not fail the list, so they resolve
      // separately.
      final plansFuture = _loadPlans(event.gymId);
      final ranksFuture = _loadRanks(event.gymId);

      final results = await Future.wait([
        _repository.getMembersList(request),
        _repository.getTotalCounts(event.gymId),
      ]);

      final listResponse =
          results[0] as CrmMembersListResponse;
      final totalCounts =
          results[1] as MembersListTotalCounts;
      final plans = await plansFuture;
      final ranks = await ranksFuture;

      emit(MembersListLoaded(
        gymId: event.gymId,
        activeView: MembersListView.all,
        filters: listResponse.filters,
        plans: plans,
        ranks: ranks,
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

    // Only the view (row shape) changes — every active filter
    // is kept exactly as set.
    await _fetchFreshPage(
      emit: emit,
      gymId: currentState.gymId,
      view: event.newView,
      filters: currentState.filters,
      plans: currentState.plans,
      ranks: currentState.ranks,
      totalCounts: currentState.totalCounts,
      searchQuery: currentState.searchQuery,
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

    await _fetchFreshPage(
      emit: emit,
      gymId: currentState.gymId,
      view: currentState.activeView,
      filters: currentState.filters.copyWith(
        membershipStatus: newStatuses,
      ),
      plans: currentState.plans,
      ranks: currentState.ranks,
      totalCounts: currentState.totalCounts,
      searchQuery: currentState.searchQuery,
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

    await _fetchFreshPage(
      emit: emit,
      gymId: currentState.gymId,
      view: currentState.activeView,
      filters: currentState.filters.copyWith(
        membershipStatus: newStatuses,
      ),
      plans: currentState.plans,
      ranks: currentState.ranks,
      totalCounts: currentState.totalCounts,
      searchQuery: currentState.searchQuery,
    );
  }

  Future<void> _onPlanFilterRemoved(
    MembersListPlanFilterRemoved event,
    Emitter<MembersListState> emit,
  ) async {
    final currentState = state;
    if (currentState is! MembersListLoaded) return;

    final newPlanIds = currentState.filters.planIds
        .where((id) => id != event.planId)
        .toList();

    await _fetchFreshPage(
      emit: emit,
      gymId: currentState.gymId,
      view: currentState.activeView,
      filters: currentState.filters.copyWith(
        planIds: newPlanIds,
      ),
      plans: currentState.plans,
      ranks: currentState.ranks,
      totalCounts: currentState.totalCounts,
      searchQuery: currentState.searchQuery,
    );
  }

  Future<void> _onRankFilterRemoved(
    MembersListRankFilterRemoved event,
    Emitter<MembersListState> emit,
  ) async {
    final currentState = state;
    if (currentState is! MembersListLoaded) return;

    final newRankIds = currentState.filters.rankIds
        .where((id) => id != event.rankId)
        .toList();

    await _fetchFreshPage(
      emit: emit,
      gymId: currentState.gymId,
      view: currentState.activeView,
      filters: currentState.filters.copyWith(
        rankIds: newRankIds,
      ),
      plans: currentState.plans,
      ranks: currentState.ranks,
      totalCounts: currentState.totalCounts,
      searchQuery: currentState.searchQuery,
    );
  }

  Future<void> _onDateRangeFilterSet(
    MembersListDateRangeFilterSet event,
    Emitter<MembersListState> emit,
  ) async {
    final currentState = state;
    if (currentState is! MembersListLoaded) return;

    await _fetchFreshPage(
      emit: emit,
      gymId: currentState.gymId,
      view: currentState.activeView,
      filters: currentState.filters.copyWith(
        dateRange: event.dateRange,
      ),
      plans: currentState.plans,
      ranks: currentState.ranks,
      totalCounts: currentState.totalCounts,
      searchQuery: currentState.searchQuery,
    );
  }

  Future<void> _onFiltersApplied(
    MembersListFiltersApplied event,
    Emitter<MembersListState> emit,
  ) async {
    final currentState = state;
    if (currentState is! MembersListLoaded) return;

    await _fetchFreshPage(
      emit: emit,
      gymId: currentState.gymId,
      view: currentState.activeView,
      filters: event.filters,
      plans: currentState.plans,
      ranks: currentState.ranks,
      totalCounts: currentState.totalCounts,
      searchQuery: currentState.searchQuery,
    );
  }

  Future<void> _onDateRangeFilterCleared(
    MembersListDateRangeFilterCleared event,
    Emitter<MembersListState> emit,
  ) async {
    final currentState = state;
    if (currentState is! MembersListLoaded) return;

    await _fetchFreshPage(
      emit: emit,
      gymId: currentState.gymId,
      view: currentState.activeView,
      filters: currentState.filters.copyWith(
        clearDateRange: true,
      ),
      plans: currentState.plans,
      ranks: currentState.ranks,
      totalCounts: currentState.totalCounts,
      searchQuery: currentState.searchQuery,
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
        view: currentState.activeView,
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
        displayedRows: allRows,
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

  Future<void> _onSearchChanged(
    MembersListSearchChanged event,
    Emitter<MembersListState> emit,
  ) async {
    final currentState = state;
    if (currentState is! MembersListLoaded) return;

    final trimmed = event.query.trim();
    final isEmpty = trimmed.isEmpty;

    final newFilters = currentState.filters.copyWith(
      name: isEmpty ? null : trimmed,
      clearName: isEmpty,
    );

    final seq = ++_searchSeq;

    emit(currentState.copyWith(
      searchQuery: event.query,
      isLoadingMore: true,
    ));

    try {
      final request = CrmMembersListRequest(
        gymId: currentState.gymId,
        view: currentState.activeView,
        filters: newFilters,
      );

      final response =
          await _repository.getMembersList(request);

      if (seq != _searchSeq) return;

      final afterState = state;
      if (afterState is! MembersListLoaded) return;

      final rows =
          List<MemberRow>.from(response.data);

      emit(afterState.copyWith(
        filters: response.filters,
        allRows: rows,
        displayedRows: rows,
        searchQuery: event.query,
        startIndex: 0,
        hasReachedEnd: response.data.length <
            AppConstants.defaultPageSize,
        isLoadingMore: false,
      ));
    } catch (e, stackTrace) {
      log(
        'Failed to search members',
        error: e,
        stackTrace: stackTrace,
      );
      if (seq != _searchSeq) return;
      final afterState = state;
      if (afterState is MembersListLoaded) {
        emit(afterState.copyWith(isLoadingMore: false));
      }
    }
  }

  /// Fetches a fresh first page after a view or filter
  /// change. Resets pagination; keeps the loaded plans + ranks.
  Future<void> _fetchFreshPage({
    required Emitter<MembersListState> emit,
    required String gymId,
    required MembersListView view,
    required MembersListFilters filters,
    required List<MembershipPlanResponse> plans,
    required List<MainRank> ranks,
    required MembersListTotalCounts totalCounts,
    String searchQuery = '',
  }) async {
    emit(const MembersListLoading());

    try {
      final request = CrmMembersListRequest(
        gymId: gymId,
        view: view,
        filters: filters,
      );

      final response =
          await _repository.getMembersList(request);

      final rows =
          List<MemberRow>.from(response.data);

      emit(MembersListLoaded(
        gymId: gymId,
        activeView: view,
        filters: response.filters,
        plans: plans,
        ranks: ranks,
        allRows: rows,
        displayedRows: rows,
        searchQuery: searchQuery,
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

  /// Loads the gym's membership plans for the filter picker.
  /// Best-effort: a failure degrades to an empty list (the
  /// plan filter section just won't show) rather than failing
  /// the whole members list.
  Future<List<MembershipPlanResponse>> _loadPlans(
    String gymId,
  ) async {
    try {
      return await _membershipsRepository.listPlans(gymId);
    } catch (e, stackTrace) {
      log(
        'Failed to load plans for members filter',
        error: e,
        stackTrace: stackTrace,
      );
      return const [];
    }
  }

  /// Loads the gym's main ranks for the filter picker. Best-effort:
  /// a failure degrades to an empty list (the rank filter section
  /// just won't show) rather than failing the whole members list —
  /// mirrors [_loadPlans].
  Future<List<MainRank>> _loadRanks(String gymId) async {
    try {
      final ladder = await _ranksRepository.listRanks(gymId);
      return ladder.ranks;
    } catch (e, stackTrace) {
      log(
        'Failed to load ranks for members filter',
        error: e,
        stackTrace: stackTrace,
      );
      return const [];
    }
  }
}
