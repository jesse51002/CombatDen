import 'package:json_annotation/json_annotation.dart';

part 'rank_create_request.g.dart';

/// Body for `POST /api/v1/ranks/`. `color` is a `#RRGGBB` hex
/// string; `imageUrl` is an optional belt-graphic URL.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  includeIfNull: false,
  createFactory: false,
)
class RankCreateRequest {
  final String gymId;
  final int mainRankNumOrder;
  final int subRankNumOrder;
  final String mainName;
  final String subName;
  final int classesTillRankup;
  final String? imageUrl;
  final String? color;

  const RankCreateRequest({
    required this.gymId,
    required this.mainRankNumOrder,
    required this.subRankNumOrder,
    required this.mainName,
    required this.subName,
    required this.classesTillRankup,
    this.imageUrl,
    this.color,
  });

  Map<String, dynamic> toJson() => _$RankCreateRequestToJson(this);
}
