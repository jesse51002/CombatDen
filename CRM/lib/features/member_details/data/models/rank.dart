import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'rank.g.dart';

/// A member's current rank (belt).
///
/// Mirrors the merged `BillingRank` schema — sourced from the
/// member's `current_rank_id` row in `gym_ranks`. Null on the
/// response when the member has no rank assigned.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class Rank extends Equatable {
  final String rankId;
  final String mainName;
  final String subName;
  final String? imageUrl;
  final String? color;
  final int classesTillRankup;

  /// Classes the member has attended since their last promotion —
  /// the real progress numerator toward [classesTillRankup].
  @JsonKey(defaultValue: 0)
  final int classesSinceRank;

  const Rank({
    required this.rankId,
    required this.mainName,
    required this.subName,
    this.imageUrl,
    this.color,
    required this.classesTillRankup,
    this.classesSinceRank = 0,
  });

  factory Rank.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$RankFromJson(json);

  /// Combined belt label, e.g. "Purple · 1 stripe".
  String get displayLabel => '$mainName · $subName';

  @override
  List<Object?> get props => [
        rankId,
        mainName,
        subName,
        imageUrl,
        color,
        classesTillRankup,
        classesSinceRank,
      ];
}
