import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/core/constants/app_constants.dart';
import 'package:crm/features/memberships/bloc/ready_to_promote/ready_to_promote_event.dart';
import 'package:crm/features/memberships/bloc/ready_to_promote/ready_to_promote_state.dart';
import 'package:crm/features/memberships/data/models/rank_ladder.dart';
import 'package:crm/features/memberships/data/models/rank_ready_row.dart';
import 'package:crm/features/memberships/data/repositories/ranks_repository.dart';

/// Manages the ready-to-promote board: the gym's ladder (to resolve a
/// dialog-picked promotion) plus a paginated, proximity-sorted roster of
/// members closest to their next leaf.
class ReadyToPromoteBloc
    extends Bloc<ReadyToPromoteEvent, ReadyToPromoteState> {
  final RanksRepository _repository;

  ReadyToPromoteBloc({required RanksRepository repository})
      : _repository = repository,
        super(const ReadyToPromoteInitial()) {
    on<ReadyToPromoteInitRequested>(_onInitRequested);
    on<ReadyToPromoteNextPageRequested>(_onNextPageRequested);
    on<ReadyPromoteRequested>(_onPromoteRequested);
  }

  Future<void> _onInitRequested(
    ReadyToPromoteInitRequested event,
    Emitter<ReadyToPromoteState> emit,
  ) async {
    emit(const ReadyToPromoteLoading());
    try {
      final results = await Future.wait([
        _repository.listRanks(event.gymId),
        _repository.readyToPromote(event.gymId),
      ]);
      final ladder = results[0] as RankLadder;
      final page =
          results[1] as (List<RankReadyRow> items, int totalCount);
      emit(ReadyToPromoteLoaded(
        gymId: event.gymId,
        ladder: ladder.ranks,
        subRankType: ladder.subRankType,
        rows: page.$1,
        totalCount: page.$2,
        hasReachedEnd: page.$1.length < AppConstants.defaultPageSize,
      ));
    } catch (e, stackTrace) {
      log('Failed to load ready-to-promote board',
          error: e, stackTrace: stackTrace);
      emit(ReadyToPromoteError(e.toString(), gymId: event.gymId));
    }
  }

  Future<void> _onNextPageRequested(
    ReadyToPromoteNextPageRequested event,
    Emitter<ReadyToPromoteState> emit,
  ) async {
    final current = state;
    if (current is! ReadyToPromoteLoaded) return;
    if (current.isLoadingMore || current.hasReachedEnd) return;

    final nextIndex = current.startIndex + AppConstants.defaultPageSize;
    emit(current.copyWith(isLoadingMore: true));

    try {
      final page = await _repository.readyToPromote(
        current.gymId,
        startIndex: nextIndex,
      );
      final afterState = state;
      if (afterState is! ReadyToPromoteLoaded) return;

      final rows = [...afterState.rows, ...page.$1];
      emit(afterState.copyWith(
        rows: rows,
        totalCount: page.$2,
        startIndex: nextIndex,
        hasReachedEnd: page.$1.length < AppConstants.defaultPageSize,
        isLoadingMore: false,
      ));
    } catch (e, stackTrace) {
      log('Failed to load next page of ready-to-promote board',
          error: e, stackTrace: stackTrace);
      final afterState = state;
      if (afterState is ReadyToPromoteLoaded) {
        emit(afterState.copyWith(isLoadingMore: false));
      }
    }
  }

  Future<void> _onPromoteRequested(
    ReadyPromoteRequested event,
    Emitter<ReadyToPromoteState> emit,
  ) async {
    final current = state;
    if (current is! ReadyToPromoteLoaded) return;
    emit(current.copyWith(isMutating: true, clearActionError: true));

    final row = current.rows.where((r) => r.memberId == event.memberId);
    final currentMainRankId = row.isEmpty ? null : row.first.mainRankId;

    try {
      await _repository.applyPromotion(
        gymId: current.gymId,
        memberId: event.memberId,
        choice: event.choice,
        currentMainRankId: currentMainRankId,
        ladder: current.ladder,
      );
      final page = await _repository.readyToPromote(current.gymId);
      final afterState = state;
      if (afterState is! ReadyToPromoteLoaded) return;
      emit(afterState.copyWith(
        rows: page.$1,
        totalCount: page.$2,
        startIndex: 0,
        hasReachedEnd: page.$1.length < AppConstants.defaultPageSize,
        isMutating: false,
        actionSuccessCount: afterState.actionSuccessCount + 1,
      ));
    } catch (e, stackTrace) {
      log('Ready-to-promote promote failed',
          error: e, stackTrace: stackTrace);
      final afterState = state;
      if (afterState is ReadyToPromoteLoaded) {
        emit(afterState.copyWith(
          isMutating: false,
          actionError: e.toString(),
        ));
      }
    }
  }
}
