import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/app_constants.dart';
import 'package:crm/features/memberships/bloc/rank_detail/rank_detail_event.dart';
import 'package:crm/features/memberships/bloc/rank_detail/rank_detail_state.dart';
import 'package:crm/features/memberships/data/models/main_rank.dart';
import 'package:crm/features/memberships/data/models/rank_ladder.dart';
import 'package:crm/features/memberships/data/models/rank_member_row.dart';
import 'package:crm/features/memberships/data/models/rank_sub_rank_counts.dart';
import 'package:crm/features/memberships/data/repositories/ranks_repository.dart';

/// Manages one rank's detail view: header + the gym's ladder +
/// paginated roster of members currently on the rank, plus
/// per-member promote (with an in-place reload of page one so a
/// promoted member drops off the list).
class RankDetailBloc extends Bloc<RankDetailEvent, RankDetailState> {
  final RanksRepository _repository;

  RankDetailBloc({required RanksRepository repository})
      : _repository = repository,
        super(const RankDetailInitial()) {
    on<RankDetailInitRequested>(_onInitRequested);
    on<RankDetailNextPageRequested>(_onNextPageRequested);
    on<RankDetailPromoteRequested>(_onPromoteRequested);
    on<RankDetailDeleteRequested>(_onDeleteRequested);
  }

  Future<void> _onInitRequested(
    RankDetailInitRequested event,
    Emitter<RankDetailState> emit,
  ) async {
    emit(const RankDetailLoading());
    try {
      // The counts read is guarded on its own so a missing/failing
      // sub-rank-counts endpoint degrades to "total only" instead of
      // failing the whole page — it rides alongside the core reads,
      // never gating them.
      final countsFuture = _repository
          .subRankCounts(event.rankId)
          .then<RankSubRankCounts?>((v) => v)
          .catchError((Object e, StackTrace st) {
        log('Failed to load sub-rank counts', error: e, stackTrace: st);
        return null;
      });
      final results = await Future.wait([
        _repository.getRank(event.rankId),
        _repository.listRanks(event.gymId),
        _repository.membersInRank(event.gymId, event.rankId),
      ]);
      final rank = results[0] as MainRank;
      final ladder = results[1] as RankLadder;
      final page =
          results[2] as (List<RankMemberRow> items, int totalCount);
      final counts = await countsFuture;
      emit(RankDetailLoaded(
        gymId: event.gymId,
        rank: rank,
        ladder: ladder.ranks,
        subRankType: ladder.subRankType,
        members: page.$1,
        subRankCounts: counts,
        totalCount: page.$2,
        hasReachedEnd: page.$1.length < AppConstants.defaultPageSize,
      ));
    } catch (e, stackTrace) {
      log('Failed to load rank detail', error: e, stackTrace: stackTrace);
      emit(RankDetailError(
        e.toString(),
        gymId: event.gymId,
        rankId: event.rankId,
      ));
    }
  }

  Future<void> _onNextPageRequested(
    RankDetailNextPageRequested event,
    Emitter<RankDetailState> emit,
  ) async {
    final current = state;
    if (current is! RankDetailLoaded) return;
    if (current.isLoadingMore || current.hasReachedEnd) return;

    final nextIndex = current.startIndex + AppConstants.defaultPageSize;
    emit(current.copyWith(isLoadingMore: true));

    try {
      final page = await _repository.membersInRank(
        current.gymId,
        current.rank.rankId,
        startIndex: nextIndex,
      );
      final afterState = state;
      if (afterState is! RankDetailLoaded) return;

      final members = [...afterState.members, ...page.$1];
      emit(afterState.copyWith(
        members: members,
        totalCount: page.$2,
        startIndex: nextIndex,
        hasReachedEnd: page.$1.length < AppConstants.defaultPageSize,
        isLoadingMore: false,
      ));
    } catch (e, stackTrace) {
      log('Failed to load next page of rank members',
          error: e, stackTrace: stackTrace);
      final afterState = state;
      if (afterState is RankDetailLoaded) {
        emit(afterState.copyWith(isLoadingMore: false));
      }
    }
  }

  Future<void> _onPromoteRequested(
    RankDetailPromoteRequested event,
    Emitter<RankDetailState> emit,
  ) async {
    final current = state;
    if (current is! RankDetailLoaded) return;
    emit(current.copyWith(isMutating: true, clearActionError: true));

    try {
      await _repository.applyPromotion(
        gymId: current.gymId,
        memberId: event.memberId,
        choice: event.choice,
        currentMainRankId: current.rank.rankId,
        ladder: current.ladder,
      );
      final page = await _repository.membersInRank(
        current.gymId,
        current.rank.rankId,
      );
      final afterState = state;
      if (afterState is! RankDetailLoaded) return;
      emit(afterState.copyWith(
        members: page.$1,
        totalCount: page.$2,
        startIndex: 0,
        hasReachedEnd: page.$1.length < AppConstants.defaultPageSize,
        isMutating: false,
        actionSuccessCount: afterState.actionSuccessCount + 1,
      ));
    } catch (e, stackTrace) {
      log('Rank detail promote failed', error: e, stackTrace: stackTrace);
      final afterState = state;
      if (afterState is RankDetailLoaded) {
        emit(afterState.copyWith(
          isMutating: false,
          actionError: e.toString(),
        ));
      }
    }
  }

  Future<void> _onDeleteRequested(
    RankDetailDeleteRequested event,
    Emitter<RankDetailState> emit,
  ) async {
    final current = state;
    if (current is! RankDetailLoaded) return;
    emit(current.copyWith(isMutating: true, clearActionError: true));

    try {
      // The backend reassigns this rank's members to a neighbour rank
      // before deleting it. Don't re-fetch the (now-gone) rank — the
      // screen pops on the deleteSuccessCount bump.
      await _repository.deleteRank(current.rank.rankId);
      final afterState = state;
      if (afterState is! RankDetailLoaded) return;
      emit(afterState.copyWith(
        isMutating: false,
        deleteSuccessCount: afterState.deleteSuccessCount + 1,
      ));
    } catch (e, stackTrace) {
      log('Rank detail delete failed', error: e, stackTrace: stackTrace);
      final afterState = state;
      if (afterState is RankDetailLoaded) {
        emit(afterState.copyWith(
          isMutating: false,
          actionError: e.toString(),
        ));
      }
    }
  }
}
