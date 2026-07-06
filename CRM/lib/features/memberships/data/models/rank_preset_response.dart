import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/memberships/data/models/rank_preset_kind.dart';
import 'package:crm/features/memberships/data/models/rank_sub_type.dart';

part 'rank_preset_response.g.dart';

/// A single `rank_presets` row — one MAIN rank of a preset ladder
/// (main-row shape, matching [MainRank] plus its preset keying).
///
/// The grouped catalog (`GET /api/v1/ranks/presets/grouped`) is a
/// `Map<String, List<RankPresetResponse>>` keyed by [presetKind]'s
/// raw value; [implied_sub_rank_type] is `null` for a preset with no
/// sub-ranks (the flat preset), and set on the stripes preset — the
/// value the gym's `sub_rank_type` is copied to when seeded.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class RankPresetResponse extends Equatable {
  final String presetId;

  @JsonKey(fromJson: RankPresetKind.fromJson)
  final RankPresetKind presetKind;

  final int mainRankNumOrder;
  final String name;
  final String? imageUrl;
  final int classesToNextMajor;
  final int subRankCount;

  @JsonKey(fromJson: RankSubType.fromJsonNullable)
  final RankSubType? impliedSubRankType;

  const RankPresetResponse({
    required this.presetId,
    required this.presetKind,
    required this.mainRankNumOrder,
    required this.name,
    this.imageUrl,
    required this.classesToNextMajor,
    this.subRankCount = 0,
    this.impliedSubRankType,
  });

  factory RankPresetResponse.fromJson(Map<String, dynamic> json) =>
      _$RankPresetResponseFromJson(json);

  @override
  List<Object?> get props => [
        presetId,
        presetKind,
        mainRankNumOrder,
        name,
        imageUrl,
        classesToNextMajor,
        subRankCount,
        impliedSubRankType,
      ];
}
