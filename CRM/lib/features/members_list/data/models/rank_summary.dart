import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'rank_summary.g.dart';

/// Lightweight rank descriptor attached to a member row
/// or member detail.
///
/// Mirrors the merged backend `RankSummary` schema.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class RankSummary extends Equatable {
  final String rankId;
  final String mainName;
  final String subName;
  final String? color;
  final String? imageUrl;
  final int mainRankNumOrder;
  final int subRankNumOrder;

  const RankSummary({
    required this.rankId,
    required this.mainName,
    required this.subName,
    this.color,
    this.imageUrl,
    required this.mainRankNumOrder,
    required this.subRankNumOrder,
  });

  factory RankSummary.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$RankSummaryFromJson(json);

  /// Display label combining the main and sub rank names.
  String get displayName =>
      subName.isEmpty ? mainName : '$mainName — $subName';

  @override
  List<Object?> get props => [
        rankId,
        mainName,
        subName,
        color,
        imageUrl,
        mainRankNumOrder,
        subRankNumOrder,
      ];
}
