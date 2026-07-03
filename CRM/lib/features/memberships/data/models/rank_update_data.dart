import 'package:json_annotation/json_annotation.dart';

part 'rank_update_data.g.dart';

/// Mutable fields for `PUT /api/v1/ranks/{rank_id}` (sent nested
/// under `{"data": …}`). Only the fields that change are included —
/// `includeIfNull: false` omits the rest so an edit touches only
/// what the user changed.
///
/// Order columns are deliberately absent (`POST /ranks/reorder` is
/// the only mover), and so is `imageUrl` — rank belt images are
/// generation-owned (theme-styled art), never set by hand.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  includeIfNull: false,
  createFactory: false,
)
class RankUpdateData {
  final String? mainName;
  final String? subName;
  final int? classesTillRankup;
  final String? color;

  const RankUpdateData({
    this.mainName,
    this.subName,
    this.classesTillRankup,
    this.color,
  });

  Map<String, dynamic> toJson() => _$RankUpdateDataToJson(this);
}
