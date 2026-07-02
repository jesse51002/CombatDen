import 'package:json_annotation/json_annotation.dart';

part 'rank_preset_group.g.dart';

/// One sub-rank within a preset's main-rank group, from
/// `GET /api/v1/ranks/presets/grouped`.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class RankSubPreset {
  final String presetId;
  final int subRankNumOrder;
  final String subName;
  final int classesTillRankup;
  final String? imageUrl;
  final String? color;

  const RankSubPreset({
    required this.presetId,
    required this.subRankNumOrder,
    required this.subName,
    required this.classesTillRankup,
    required this.imageUrl,
    required this.color,
  });

  factory RankSubPreset.fromJson(Map<String, dynamic> json) =>
      _$RankSubPresetFromJson(json);
}

/// A preset main rank with its ordered sub-ranks nested beneath.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class RankPresetGroup {
  final int mainRankNumOrder;
  final String mainName;
  final List<RankSubPreset> subRanks;

  const RankPresetGroup({
    required this.mainRankNumOrder,
    required this.mainName,
    required this.subRanks,
  });

  factory RankPresetGroup.fromJson(Map<String, dynamic> json) =>
      _$RankPresetGroupFromJson(json);
}
