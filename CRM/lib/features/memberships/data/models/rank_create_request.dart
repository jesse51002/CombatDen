import 'package:json_annotation/json_annotation.dart';

part 'rank_create_request.g.dart';

/// Body for `POST /api/v1/ranks/`. `color` is a `#RRGGBB` hex
/// string. There is no image field — rank belt images are
/// generation-owned (theme-styled art), never provided at create.
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
  final String? color;

  const RankCreateRequest({
    required this.gymId,
    required this.mainRankNumOrder,
    required this.subRankNumOrder,
    required this.mainName,
    required this.subName,
    required this.classesTillRankup,
    this.color,
  });

  Map<String, dynamic> toJson() => _$RankCreateRequestToJson(this);
}
