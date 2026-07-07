import 'package:equatable/equatable.dart';

import 'package:crm/features/memberships/data/models/main_rank.dart';
import 'package:crm/features/memberships/data/models/rank_sub_type.dart';

sealed class RanksState extends Equatable {
  const RanksState();

  @override
  List<Object?> get props => [];
}

class RanksInitial extends RanksState {
  const RanksInitial();
}

class RanksLoading extends RanksState {
  const RanksLoading();
}

class RanksLoaded extends RanksState {
  final String gymId;

  /// The ordered main-rank ladder.
  final List<MainRank> ranks;

  /// The gym's sub-rank type — derives every row's sub-rank labels.
  final RankSubType subRankType;

  /// Whether the gym's rank system is on.
  final bool isRankEnabled;

  /// True while a create/update/delete/reorder/toggle is in flight.
  final bool isMutating;

  /// Set when the last mutation failed; cleared on the next load.
  final String? actionError;

  /// Monotonic counter bumped on every successful mutation-reload
  /// (create / update / delete / reorder / toggle / sub-type / seed). Lets
  /// sibling surfaces — the ready-to-promote board — reload when the ladder
  /// changes under them.
  final int mutationCount;

  const RanksLoaded({
    required this.gymId,
    required this.ranks,
    required this.subRankType,
    required this.isRankEnabled,
    this.isMutating = false,
    this.actionError,
    this.mutationCount = 0,
  });

  RanksLoaded copyWith({
    List<MainRank>? ranks,
    RankSubType? subRankType,
    bool? isRankEnabled,
    bool? isMutating,
    String? actionError,
    int? mutationCount,
  }) {
    return RanksLoaded(
      gymId: gymId,
      ranks: ranks ?? this.ranks,
      subRankType: subRankType ?? this.subRankType,
      isRankEnabled: isRankEnabled ?? this.isRankEnabled,
      isMutating: isMutating ?? this.isMutating,
      actionError: actionError,
      mutationCount: mutationCount ?? this.mutationCount,
    );
  }

  @override
  List<Object?> get props => [
        gymId,
        ranks,
        subRankType,
        isRankEnabled,
        isMutating,
        actionError,
        mutationCount,
      ];
}

class RanksError extends RanksState {
  final String message;
  final String gymId;

  const RanksError(this.message, {required this.gymId});

  @override
  List<Object?> get props => [message, gymId];
}
