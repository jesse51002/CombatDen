import 'package:json_annotation/json_annotation.dart';

import 'package:mobile_app/features/videos/data/models/gym_video_card.dart';
import 'package:mobile_app/features/videos/data/models/video_genre.dart';

part 'member_video_rec.g.dart';

/// One recommendation served to a member — the single rotating-category pick.
///
/// Mirrors `MemberVideoRec` in
/// `FastApiBackend/src/videos/schema/video_recs_schema.py`
/// (`GET /api/v1/member/gyms/{gid}/members/{mid}/video-rec`). [recId] is the
/// just-written serve row; the client posts it back to the click route when
/// the member opens the rec. [category] is the served video's genre; [video]
/// is the card (carrying its own `video_id`).
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class MemberVideoRec {
  final String recId;

  @JsonKey(fromJson: videoGenreFromJson)
  final VideoGenre category;

  final GymVideoCard video;

  const MemberVideoRec({
    required this.recId,
    required this.category,
    required this.video,
  });

  factory MemberVideoRec.fromJson(Map<String, dynamic> json) =>
      _$MemberVideoRecFromJson(json);
}
