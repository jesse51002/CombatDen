import 'package:json_annotation/json_annotation.dart';

import 'package:mobile_app/features/profile/data/models/rank_progress_point.dart';

part 'member_rank_progress.g.dart';

/// The member's rank-progress series — one point per activity event, backing
/// the profile's rank graph.
///
/// Mirrors `MemberRankProgressResponse` in
/// `FastApiBackend/src/member_portal/schema/member_portal_schema.py`
/// (`GET /api/v1/member/gyms/{gid}/members/{mid}/rank-progress`). [points] is
/// an empty list (a valid 200) when the member holds no rank or the gym has
/// ranks disabled.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class MemberRankProgress {
  @JsonKey(defaultValue: <RankProgressPoint>[])
  final List<RankProgressPoint> points;

  const MemberRankProgress({this.points = const []});

  factory MemberRankProgress.fromJson(Map<String, dynamic> json) =>
      _$MemberRankProgressFromJson(json);
}
