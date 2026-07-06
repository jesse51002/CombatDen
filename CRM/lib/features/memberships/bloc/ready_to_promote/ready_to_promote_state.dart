import 'package:equatable/equatable.dart';

import 'package:crm/features/memberships/data/models/main_rank.dart';
import 'package:crm/features/memberships/data/models/rank_ready_row.dart';
import 'package:crm/features/memberships/data/models/rank_sub_type.dart';

sealed class ReadyToPromoteState extends Equatable {
  const ReadyToPromoteState();

  @override
  List<Object?> get props => [];
}

class ReadyToPromoteInitial extends ReadyToPromoteState {
  const ReadyToPromoteInitial();
}

class ReadyToPromoteLoading extends ReadyToPromoteState {
  const ReadyToPromoteLoading();
}

class ReadyToPromoteLoaded extends ReadyToPromoteState {
  final String gymId;

  /// The gym's full ordered ladder — needed to resolve a
  /// `PromoteNextMajor` choice for any row on the board (each row
  /// may be on a different main rank).
  final List<MainRank> ladder;

  /// The gym's sub-rank type — derives every sub-rank label the
  /// promotion dialog renders.
  final RankSubType subRankType;

  /// Rows loaded so far (across pages), proximity-sorted.
  final List<RankReadyRow> rows;

  final int totalCount;
  final int startIndex;
  final bool hasReachedEnd;
  final bool isLoadingMore;

  /// True while a promote is in flight.
  final bool isMutating;

  /// Set when the last promote failed; cleared on the next load.
  final String? actionError;

  /// Monotonic token bumped on every successful promote, so a
  /// listener can show a one-shot confirmation.
  final int actionSuccessCount;

  const ReadyToPromoteLoaded({
    required this.gymId,
    required this.ladder,
    required this.subRankType,
    required this.rows,
    this.totalCount = 0,
    this.startIndex = 0,
    this.hasReachedEnd = false,
    this.isLoadingMore = false,
    this.isMutating = false,
    this.actionError,
    this.actionSuccessCount = 0,
  });

  ReadyToPromoteLoaded copyWith({
    List<MainRank>? ladder,
    RankSubType? subRankType,
    List<RankReadyRow>? rows,
    int? totalCount,
    int? startIndex,
    bool? hasReachedEnd,
    bool? isLoadingMore,
    bool? isMutating,
    String? actionError,
    bool clearActionError = false,
    int? actionSuccessCount,
  }) {
    return ReadyToPromoteLoaded(
      gymId: gymId,
      ladder: ladder ?? this.ladder,
      subRankType: subRankType ?? this.subRankType,
      rows: rows ?? this.rows,
      totalCount: totalCount ?? this.totalCount,
      startIndex: startIndex ?? this.startIndex,
      hasReachedEnd: hasReachedEnd ?? this.hasReachedEnd,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isMutating: isMutating ?? this.isMutating,
      actionError:
          clearActionError ? null : (actionError ?? this.actionError),
      actionSuccessCount: actionSuccessCount ?? this.actionSuccessCount,
    );
  }

  @override
  List<Object?> get props => [
        gymId,
        ladder,
        subRankType,
        rows,
        totalCount,
        startIndex,
        hasReachedEnd,
        isLoadingMore,
        isMutating,
        actionError,
        actionSuccessCount,
      ];
}

class ReadyToPromoteError extends ReadyToPromoteState {
  final String message;
  final String gymId;

  const ReadyToPromoteError(this.message, {required this.gymId});

  @override
  List<Object?> get props => [message, gymId];
}
