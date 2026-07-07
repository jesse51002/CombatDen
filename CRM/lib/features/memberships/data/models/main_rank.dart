import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'main_rank.g.dart';

/// A single `gym_ranks` row — one MAIN rank on a gym's ladder.
///
/// Mirrors the backend `RankResponse`. `subRankCount == 0` means this
/// main rank is itself the leaf (a member on it has no sub-index);
/// `N >= 1` means `N` leaf sub-positions (`sub_index` in
/// `[0, N - 1]`). Sub-rank LABELS are derived from the gym's
/// [RankSubType] + the index — this row never carries a label
/// itself. Read-only (`createToJson: false`); the API is the source
/// of truth.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class MainRank extends Equatable {
  final String rankId;
  final String gymId;
  final int mainRankNumOrder;
  final String name;
  final String? imageUrl;
  final int classesToNextMajor;
  final int subRankCount;

  /// Per-sub-index image overrides (`"0" -> url`), persist-only — a
  /// count shrink, a gym sub-rank-type change, or any revert never
  /// prunes this map. Use [imageForSub] to resolve the effective
  /// image for a leaf.
  @JsonKey(defaultValue: <String, String>{})
  final Map<String, String> subRankImageOverrides;

  final DateTime createdAt;

  const MainRank({
    required this.rankId,
    required this.gymId,
    required this.mainRankNumOrder,
    required this.name,
    this.imageUrl,
    required this.classesToNextMajor,
    this.subRankCount = 0,
    this.subRankImageOverrides = const {},
    required this.createdAt,
  });

  factory MainRank.fromJson(Map<String, dynamic> json) =>
      _$MainRankFromJson(json);

  /// The effective image for leaf [index]: its override if one was
  /// ever written, else [fallback] if given, else this rank's own
  /// [imageUrl].
  String? imageForSub(int index, {String? fallback}) =>
      subRankImageOverrides[index.toString()] ?? fallback ?? imageUrl;

  @override
  List<Object?> get props => [
        rankId,
        gymId,
        mainRankNumOrder,
        name,
        imageUrl,
        classesToNextMajor,
        subRankCount,
        subRankImageOverrides,
        createdAt,
      ];
}
