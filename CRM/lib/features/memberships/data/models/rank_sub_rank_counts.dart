import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'rank_sub_rank_counts.g.dart';

/// The member headcount on a main rank, broken down by sub-position —
/// from `GET /api/v1/ranks/{rank_id}/sub-rank-counts?gym_id=…`.
///
/// [counts] is **sparse**: only sub-positions with at least one member
/// appear (a position with nobody on it is simply absent, read as `0`).
/// A `none`-style gym (no sub-positions) returns a single entry whose
/// [RankSubRankCount.subIndex] is `null`. Use [countBySubIndex] to
/// resolve a dense `sub_index -> count` map for rendering every position.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class RankSubRankCounts extends Equatable {
  final int totalCount;
  final List<RankSubRankCount> counts;

  const RankSubRankCounts({
    required this.totalCount,
    this.counts = const [],
  });

  factory RankSubRankCounts.fromJson(Map<String, dynamic> json) =>
      _$RankSubRankCountsFromJson(json);

  /// A dense `sub_index -> count` map over the sparse [counts], dropping
  /// the `null`-index (`none`-gym) row — callers render per position
  /// index and default an absent position to `0`.
  Map<int, int> countBySubIndex() {
    final map = <int, int>{};
    for (final c in counts) {
      final index = c.subIndex;
      if (index != null) map[index] = c.count;
    }
    return map;
  }

  @override
  List<Object?> get props => [totalCount, counts];
}

/// One `{ sub_index, count }` entry of a [RankSubRankCounts]. [subIndex]
/// is `null` only for a `none`-style gym's single aggregate row.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class RankSubRankCount extends Equatable {
  final int? subIndex;
  final int count;

  const RankSubRankCount({this.subIndex, required this.count});

  factory RankSubRankCount.fromJson(Map<String, dynamic> json) =>
      _$RankSubRankCountFromJson(json);

  @override
  List<Object?> get props => [subIndex, count];
}
