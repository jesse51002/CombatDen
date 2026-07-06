import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'rank.g.dart';

/// A member's current rank (leaf).
///
/// Mirrors the backend `BillingRank` — sourced from the member's
/// `current_rank_id` (main rank) + `current_sub_index` (leaf). Null
/// on the response when the member has no rank assigned. [subIndex]
/// / [subLabel] are `null` when the rank has no sub-ranks;
/// [imageUrl] is already the leaf-resolved belt image (a per-sub
/// override if one is set, else the main rank's image).
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class Rank extends Equatable {
  final String rankId;
  final String name;
  final int? subIndex;
  final String? subLabel;
  final String? imageUrl;

  /// Headline threshold to the next MAJOR rank (gym-set).
  final int classesToNextMajor;

  /// Classes needed to reach the next LEAF — an even split of
  /// [classesToNextMajor] across sub-positions, else the full major
  /// threshold when the rank has no sub-ranks. The real denominator
  /// for the member's immediate progress.
  final int classesTillNextStep;

  /// Classes the member has attended since their last promotion —
  /// the real progress numerator toward [classesTillNextStep].
  @JsonKey(defaultValue: 0)
  final int classesSinceRank;

  const Rank({
    required this.rankId,
    required this.name,
    this.subIndex,
    this.subLabel,
    this.imageUrl,
    required this.classesToNextMajor,
    required this.classesTillNextStep,
    this.classesSinceRank = 0,
  });

  factory Rank.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$RankFromJson(json);

  /// "Blue" or "Blue · 1 Stripe" — the human label for this leaf.
  String get displayLabel =>
      subLabel == null || subLabel!.isEmpty ? name : '$name · $subLabel';

  @override
  List<Object?> get props => [
        rankId,
        name,
        subIndex,
        subLabel,
        imageUrl,
        classesToNextMajor,
        classesTillNextStep,
        classesSinceRank,
      ];
}
