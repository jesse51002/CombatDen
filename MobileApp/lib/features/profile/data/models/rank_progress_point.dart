import 'package:json_annotation/json_annotation.dart';

part 'rank_progress_point.g.dart';

/// One point in the member's rank-progress series (the profile graph).
///
/// Mirrors `RankProgressPoint` in
/// `FastApiBackend/src/member_portal/schema/member_portal_schema.py`
/// (`GET /api/v1/member/gyms/{gid}/members/{mid}/rank-progress`). [date] is the
/// gym-local day the activity happened, kept as the backend's raw ISO date
/// string (`YYYY-MM-DD`) — parsed only for the timeframe window.
/// [classesIntoRank] is classes accrued toward the next rank at this point
/// (reset to 0 at each promotion, capped at [classesNeeded]); [classesNeeded]
/// is the member's current per-step threshold (constant across the series).
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class RankProgressPoint {
  final String date;
  final int classesIntoRank;
  final int classesNeeded;

  const RankProgressPoint({
    required this.date,
    required this.classesIntoRank,
    required this.classesNeeded,
  });

  factory RankProgressPoint.fromJson(Map<String, dynamic> json) =>
      _$RankProgressPointFromJson(json);
}
