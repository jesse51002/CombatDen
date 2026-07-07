import 'package:equatable/equatable.dart';

import 'package:crm/features/memberships/data/models/main_rank.dart';
import 'package:crm/features/memberships/data/models/rank_member_row.dart';
import 'package:crm/features/memberships/data/models/rank_sub_rank_counts.dart';
import 'package:crm/features/memberships/data/models/rank_sub_type.dart';

sealed class RankDetailState extends Equatable {
  const RankDetailState();

  @override
  List<Object?> get props => [];
}

class RankDetailInitial extends RankDetailState {
  const RankDetailInitial();
}

class RankDetailLoading extends RankDetailState {
  const RankDetailLoading();
}

class RankDetailLoaded extends RankDetailState {
  final String gymId;

  /// The viewed main rank (header: name, image, thresholds).
  final MainRank rank;

  /// The gym's full ordered ladder — needed to resolve a
  /// `PromoteNextMajor` choice (the next main rank after this one).
  final List<MainRank> ladder;

  /// The gym's sub-rank type — derives every sub-rank label the
  /// promotion dialog renders.
  final RankSubType subRankType;

  /// Members currently on this rank, loaded so far (across pages),
  /// **proximity-sorted** by the backend (closest to their next leaf
  /// first — the same order as the ready-to-promote board). Rendered
  /// as a single flat list; never re-sorted or grouped client-side.
  final List<RankMemberRow> members;

  /// The member headcount on this rank broken down by sub-position
  /// (total + per-`sub_index`), for the counts summary. `null` when
  /// the counts read failed or is unavailable — the summary then falls
  /// back to the total alone (from [totalCount]) and drops the
  /// per-position breakdown.
  final RankSubRankCounts? subRankCounts;

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

  /// Monotonic token bumped once the rank is successfully deleted, so a
  /// listener can pop the screen back to the ladder (kept separate from
  /// [actionSuccessCount] so a delete never fires the promote toast).
  final int deleteSuccessCount;

  const RankDetailLoaded({
    required this.gymId,
    required this.rank,
    required this.ladder,
    required this.subRankType,
    required this.members,
    this.subRankCounts,
    this.totalCount = 0,
    this.startIndex = 0,
    this.hasReachedEnd = false,
    this.isLoadingMore = false,
    this.isMutating = false,
    this.actionError,
    this.actionSuccessCount = 0,
    this.deleteSuccessCount = 0,
  });

  RankDetailLoaded copyWith({
    MainRank? rank,
    List<MainRank>? ladder,
    RankSubType? subRankType,
    List<RankMemberRow>? members,
    RankSubRankCounts? subRankCounts,
    int? totalCount,
    int? startIndex,
    bool? hasReachedEnd,
    bool? isLoadingMore,
    bool? isMutating,
    String? actionError,
    bool clearActionError = false,
    int? actionSuccessCount,
    int? deleteSuccessCount,
  }) {
    return RankDetailLoaded(
      gymId: gymId,
      rank: rank ?? this.rank,
      ladder: ladder ?? this.ladder,
      subRankType: subRankType ?? this.subRankType,
      members: members ?? this.members,
      subRankCounts: subRankCounts ?? this.subRankCounts,
      totalCount: totalCount ?? this.totalCount,
      startIndex: startIndex ?? this.startIndex,
      hasReachedEnd: hasReachedEnd ?? this.hasReachedEnd,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isMutating: isMutating ?? this.isMutating,
      actionError:
          clearActionError ? null : (actionError ?? this.actionError),
      actionSuccessCount: actionSuccessCount ?? this.actionSuccessCount,
      deleteSuccessCount: deleteSuccessCount ?? this.deleteSuccessCount,
    );
  }

  @override
  List<Object?> get props => [
        gymId,
        rank,
        ladder,
        subRankType,
        members,
        subRankCounts,
        totalCount,
        startIndex,
        hasReachedEnd,
        isLoadingMore,
        isMutating,
        actionError,
        actionSuccessCount,
        deleteSuccessCount,
      ];
}

class RankDetailError extends RankDetailState {
  final String message;
  final String gymId;
  final String rankId;

  const RankDetailError(
    this.message, {
    required this.gymId,
    required this.rankId,
  });

  @override
  List<Object?> get props => [message, gymId, rankId];
}
