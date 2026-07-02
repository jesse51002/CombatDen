import 'package:json_annotation/json_annotation.dart';

part 'rank_enabled_response.g.dart';

/// The gym's rank-system on/off flag, from `GET/PUT
/// /api/v1/ranks/enabled`.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class RankEnabledResponse {
  final String gymId;
  final bool isRankEnabled;

  const RankEnabledResponse({
    required this.gymId,
    required this.isRankEnabled,
  });

  factory RankEnabledResponse.fromJson(Map<String, dynamic> json) =>
      _$RankEnabledResponseFromJson(json);
}
