import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/features/memberships/bloc/ranks/ranks_event.dart';
import 'package:crm/features/memberships/bloc/ranks/ranks_state.dart';
import 'package:crm/features/memberships/data/models/rank_enabled_response.dart';
import 'package:crm/features/memberships/data/models/rank_full_response.dart';
import 'package:crm/features/memberships/data/repositories/ranks_repository.dart';

/// Manages the gym's rank ladder: list + enabled flag, plus
/// create / update / delete / reorder / seed-from-preset / toggle,
/// each reloading the ladder.
class RanksBloc extends Bloc<RanksEvent, RanksState> {
  final RanksRepository _repository;

  RanksBloc({required RanksRepository repository})
      : _repository = repository,
        super(const RanksInitial()) {
    on<RanksInitRequested>(_onInitRequested);
    on<RankCreated>(_onCreated);
    on<RankUpdated>(_onUpdated);
    on<RankDeleted>(_onDeleted);
    on<RankEnabledToggled>(_onEnabledToggled);
    on<RankPresetSeeded>(_onPresetSeeded);
    on<RanksReordered>(_onReordered);
    on<RankGroupRenamed>(_onGroupRenamed);
    on<RankGroupDeleted>(_onGroupDeleted);
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

  Future<void> _onCreated(RankCreated event, Emitter<RanksState> emit) =>
      _mutateAndReload(
        emit,
        event.request.gymId,
        () => _repository.createRank(event.request),
      );

  Future<void> _onUpdated(RankUpdated event, Emitter<RanksState> emit) =>
      _mutateAndReload(
        emit,
        event.gymId,
        () => _repository.updateRank(event.rankId, event.data),
      );

  Future<void> _onDeleted(RankDeleted event, Emitter<RanksState> emit) =>
      _mutateAndReload(
        emit,
        event.gymId,
        () => _repository.deleteRank(event.rankId),
      );

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
        () => _repository.seedFromPreset(event.gymId, event.gymType),
      );

  Future<void> _onReordered(RanksReordered event, Emitter<RanksState> emit) =>
      _mutateAndReload(
        emit,
        event.gymId,
        () => _repository.reorderRanks(event.gymId, event.ranks),
      );

  Future<void> _onGroupRenamed(
    RankGroupRenamed event,
    Emitter<RanksState> emit,
  ) =>
      _mutateAndReload(
        emit,
        event.gymId,
        () => _repository.renameMainGroup(event.rankIds, event.newName),
      );

  Future<void> _onGroupDeleted(
    RankGroupDeleted event,
    Emitter<RanksState> emit,
  ) =>
      _mutateAndReload(
        emit,
        event.gymId,
        () => _repository.deleteMainGroup(event.rankIdsHighestSubFirst),
      );

  /// Fetch the ladder + enabled flag together.
  Future<RanksLoaded> _load(String gymId) async {
    final results = await Future.wait([
      _repository.listRanks(gymId),
      _repository.getRankEnabled(gymId),
    ]);
    final ranks = results[0] as List<RankFullResponse>;
    final enabled = results[1] as RankEnabledResponse;
    return RanksLoaded(
      gymId: gymId,
      ranks: ranks,
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
    if (current is RanksLoaded) {
      emit(current.copyWith(isMutating: true));
    }
    try {
      await action();
      emit(await _load(gymId));
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
