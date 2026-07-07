import 'package:json_annotation/json_annotation.dart';

part 'rank_reorder_item.g.dart';

/// One rank's target MAIN position in a `POST /api/v1/ranks/reorder`
/// payload. The full set of items is the gym's desired ladder order
/// — every rank exactly once, positions unique (sub-ranks have no
/// order of their own now — a main rank's leaves are ordered purely
/// by `sub_index`).
@JsonSerializable(fieldRename: FieldRename.snake, createFactory: false)
class RankReorderItem {
  final String rankId;
  final int mainRankNumOrder;

  const RankReorderItem({
    required this.rankId,
    required this.mainRankNumOrder,
  });

  Map<String, dynamic> toJson() => _$RankReorderItemToJson(this);
}
