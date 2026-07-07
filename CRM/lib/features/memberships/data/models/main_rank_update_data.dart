import 'package:json_annotation/json_annotation.dart';

part 'main_rank_update_data.g.dart';

/// Mutable fields for `PUT /api/v1/ranks/{rank_id}` (sent nested
/// under `{"data": …}`). Only the fields that change are included —
/// `includeIfNull: false` omits the rest so an edit touches only
/// what the user changed.
///
/// `mainRankNumOrder` is deliberately absent — `POST /ranks/reorder`
/// is the only mover of ladder positions. [imageUrl] and
/// [subRankImageOverrides] ARE writable: the belt image is a user
/// field, and the per-sub overrides map is persist-only (never
/// pruned — shrinking `subRankCount` clamps members but leaves
/// dormant overrides intact for later revival).
@JsonSerializable(
  fieldRename: FieldRename.snake,
  includeIfNull: false,
  createFactory: false,
)
class MainRankUpdateData {
  final String? name;
  final int? classesToNextMajor;
  final int? subRankCount;
  final String? imageUrl;
  final Map<String, String>? subRankImageOverrides;

  const MainRankUpdateData({
    this.name,
    this.classesToNextMajor,
    this.subRankCount,
    this.imageUrl,
    this.subRankImageOverrides,
  });

  Map<String, dynamic> toJson() => _$MainRankUpdateDataToJson(this);
}
