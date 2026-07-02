import 'package:json_annotation/json_annotation.dart';

part 'rank_full_response.g.dart';

/// A single `gym_ranks` row from `GET /api/v1/ranks/`.
///
/// Read-only (`createToJson: false`); the API is the source of
/// truth. `displayLabel` is the "Main · Sub" label used in lists.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class RankFullResponse {
  final String rankId;
  final String gymId;
  final String mainName;
  final String subName;
  final String? color;
  final String? imageUrl;
  final int mainRankNumOrder;
  final int subRankNumOrder;
  final int classesTillRankup;

  const RankFullResponse({
    required this.rankId,
    required this.gymId,
    required this.mainName,
    required this.subName,
    required this.color,
    required this.imageUrl,
    required this.mainRankNumOrder,
    required this.subRankNumOrder,
    required this.classesTillRankup,
  });

  /// "Blue · Stripe II" — the human label for a ladder rung.
  String get displayLabel => '$mainName · $subName';

  factory RankFullResponse.fromJson(Map<String, dynamic> json) =>
      _$RankFullResponseFromJson(json);
}
