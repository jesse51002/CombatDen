import 'package:json_annotation/json_annotation.dart';

part 'rank_reorder_item.g.dart';

/// One rank's target position in a `POST /api/v1/ranks/reorder`
/// payload. The full set of items is the desired ladder order.
@JsonSerializable(fieldRename: FieldRename.snake, createFactory: false)
class RankReorderItem {
  final String rankId;
  final int mainRankNumOrder;
  final int subRankNumOrder;

  const RankReorderItem({
    required this.rankId,
    required this.mainRankNumOrder,
    required this.subRankNumOrder,
  });

  Map<String, dynamic> toJson() => _$RankReorderItemToJson(this);
}
