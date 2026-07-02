import 'package:json_annotation/json_annotation.dart';

part 'rank_update_data.g.dart';

/// Mutable fields for `PUT /api/v1/ranks/{rank_id}` (sent nested
/// under `{"data": …}`). Only the fields that change are included —
/// `includeIfNull: false` omits the rest so an edit touches only
/// what the user changed.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  includeIfNull: false,
  createFactory: false,
)
class RankUpdateData {
  final String? mainName;
  final String? subName;
  final int? mainRankNumOrder;
  final int? subRankNumOrder;
  final int? classesTillRankup;
  final String? imageUrl;
  final String? color;

  const RankUpdateData({
    this.mainName,
    this.subName,
    this.mainRankNumOrder,
    this.subRankNumOrder,
    this.classesTillRankup,
    this.imageUrl,
    this.color,
  });

  Map<String, dynamic> toJson() => _$RankUpdateDataToJson(this);
}
