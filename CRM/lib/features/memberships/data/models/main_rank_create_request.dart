import 'package:json_annotation/json_annotation.dart';

part 'main_rank_create_request.g.dart';

/// Body for `POST /api/v1/ranks/`.
///
/// [imageUrl] and [subRankImageOverrides] are user-writable — the
/// belt image is a real field now (preset default now, manual
/// override in the edit page); AI generation is deferred.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  includeIfNull: false,
  createFactory: false,
)
class MainRankCreateRequest {
  final String gymId;
  final int mainRankNumOrder;
  final String name;
  final int classesToNextMajor;
  final int subRankCount;
  final String? imageUrl;
  final Map<String, String> subRankImageOverrides;

  const MainRankCreateRequest({
    required this.gymId,
    required this.mainRankNumOrder,
    required this.name,
    required this.classesToNextMajor,
    this.subRankCount = 0,
    this.imageUrl,
    this.subRankImageOverrides = const {},
  });

  Map<String, dynamic> toJson() => _$MainRankCreateRequestToJson(this);
}
