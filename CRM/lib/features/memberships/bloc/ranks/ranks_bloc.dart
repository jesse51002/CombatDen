import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/features/memberships/bloc/ranks/ranks_event.dart';
import 'package:crm/features/memberships/bloc/ranks/ranks_state.dart';
import 'package:crm/features/memberships/data/models/rank_enabled_response.dart';
import 'package:crm/features/memberships/data/models/rank_ladder.dart';
import 'package:crm/features/memberships/data/repositories/ranks_repository.dart';

/// Manages the gym's rank ladder: main ranks + sub-rank type +
/// enabled flag, plus enable-toggle / sub-type-change / seed-from-preset
/// / reorder, each reloading the ladder. Per-rank create + edit go
/// through the repository-direct `edit_rank_screen.dart`; delete goes
/// through `RankDetailBloc` — none of them run here.
class RanksBloc extends Bloc<RanksEvent, RanksState> {
  final RanksRepository _repository;

  RanksBloc({required RanksRepository repository})
      : _repository = repository,
        super(const RanksInitial()) {
    on<RanksInitRequested>(_onInitRequested);
    on<RankEnabledToggled>(_onEnabledToggled);
    on<RankPresetSeeded>(_onPresetSeeded);
    on<RanksReordered>(_onReordered);
    on<RankSubTypeChanged>(_onSubTypeChanged);
  }

  Future<void> _onInitRequested(
    RanksInitRequested event,
    Emitter<RanksState> emit,
  ) async {
    emit(const RanksLoading());
    try {
      final loaded = await _load(event.gymId);
      emit(loaded);
    } catch (e, stackTrace) {
      log('Failed to load ranks', error: e, stackTrace: stackTrace);
      emit(RanksError(e.toString(), gymId: event.gymId));
    }
  }

  Future<void> _onEnabledToggled(
    RankEnabledToggled event,
    Emitter<RanksState> emit,
  ) =>
      _mutateAndReload(
        emit,
        event.gymId,
        () => _repository.setRankEnabled(event.gymId, event.isEnabled),
      );

  Future<void> _onPresetSeeded(
    RankPresetSeeded event,
    Emitter<RanksState> emit,
  ) =>
      _mutateAndReload(
        emit,
        event.gymId,
        () => _repository.seedFromPreset(event.gymId, event.presetKind),
      );

  Future<void> _onReordered(RanksReordered event, Emitter<RanksState> emit) =>
      _mutateAndReload(
        emit,
        event.gymId,
        () => _repository.reorderRanks(event.gymId, event.ranks),
      );

  Future<void> _onSubTypeChanged(
    RankSubTypeChanged event,
    Emitter<RanksState> emit,
  ) =>
      _mutateAndReload(
        emit,
        event.gymId,
        () => _repository.setSubRankType(event.gymId, event.type),
      );

  /// Fetch the ladder (+ sub-rank type) + enabled flag together.
  Future<RanksLoaded> _load(String gymId) async {
    final results = await Future.wait([
      _repository.listRanks(gymId),
      _repository.getRankEnabled(gymId),
    ]);
    final ladder = results[0] as RankLadder;
    final enabled = results[1] as RankEnabledResponse;
    return RanksLoaded(
      gymId: gymId,
      ranks: ladder.ranks,
      subRankType: ladder.subRankType,
      isRankEnabled: enabled.isRankEnabled,
    );
  }

  /// Runs [action], then reloads. Surfaces a failed mutation via
  /// [RanksLoaded.actionError] without dropping the list (or as
  /// [RanksError] if there is no list yet).
  Future<void> _mutateAndReload(
    Emitter<RanksState> emit,
    String gymId,
    Future<void> Function() action,
  ) async {
    final current = state;
    final nextMutationCount =
        current is RanksLoaded ? current.mutationCount + 1 : 1;
    if (current is RanksLoaded) {
      emit(current.copyWith(isMutating: true));
    }
    try {
      await action();
      emit((await _load(gymId)).copyWith(mutationCount: nextMutationCount));
    } catch (e, stackTrace) {
      log('Rank mutation failed', error: e, stackTrace: stackTrace);
      if (current is RanksLoaded) {
        emit(current.copyWith(isMutating: false, actionError: e.toString()));
      } else {
        emit(RanksError(e.toString(), gymId: gymId));
      }
    }
  }
}
