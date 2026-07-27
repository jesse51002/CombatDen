import 'package:json_annotation/json_annotation.dart';

import 'package:mobile_app/features/videos/data/models/gym_video_card.dart';

part 'gym_videos_feed.g.dart';

/// One page of a gym's served video feed.
///
/// Mirrors `GymVideosFeed` in
/// `FastApiBackend/src/videos/schema/videos_schema.py`
/// (`GET /api/v1/member/gyms/{gid}/members/{mid}/videos`). [videos] is the
/// current page after the `video_type` genre filter; [total] is how many
/// matched before pagination.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class GymVideosFeed {
  final int total;
  final int limit;
  final int offset;
  final List<GymVideoCard> videos;

  const GymVideosFeed({
    required this.total,
    required this.limit,
    required this.offset,
    this.videos = const [],
  });

  factory GymVideosFeed.fromJson(Map<String, dynamic> json) =>
      _$GymVideosFeedFromJson(json);
}
