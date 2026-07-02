import 'package:equatable/equatable.dart';

import 'package:crm/features/memberships/data/models/rank_full_response.dart';

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

  /// The ordered ladder (main then sub).
  final List<RankFullResponse> ranks;

  /// Whether the gym's rank system is on.
  final bool isRankEnabled;

  /// True while a create/update/delete/reorder/toggle is in flight.
  final bool isMutating;

  /// Set when the last mutation failed; cleared on the next load.
  final String? actionError;

  const RanksLoaded({
    required this.gymId,
    required this.ranks,
    required this.isRankEnabled,
    this.isMutating = false,
    this.actionError,
  });

  RanksLoaded copyWith({
    List<RankFullResponse>? ranks,
    bool? isRankEnabled,
    bool? isMutating,
    String? actionError,
  }) {
    return RanksLoaded(
      gymId: gymId,
      ranks: ranks ?? this.ranks,
      isRankEnabled: isRankEnabled ?? this.isRankEnabled,
      isMutating: isMutating ?? this.isMutating,
      actionError: actionError,
    );
  }

  @override
  List<Object?> get props => [
        gymId,
        ranks,
        isRankEnabled,
        isMutating,
        actionError,
      ];
}

class RanksError extends RanksState {
  final String message;
  final String gymId;

  const RanksError(this.message, {required this.gymId});

  @override
  List<Object?> get props => [message, gymId];
}
