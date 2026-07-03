import 'package:json_annotation/json_annotation.dart';

part 'reward_response.g.dart';

/// API response for a single gym reward row.
/// Mirrors `RewardResponse` from `FastApiBackend/src/rewards/schema/rewards_schema.py`.
@JsonSerializable(fieldRename: FieldRename.snake)
class RewardResponse {
  final String rewardId;
  final String gymId;
  final String title;
  final int pointCost;
  final String? imageUrl;
  final String? priceLabel;
  final bool isActive;
  final DateTime createdAt;

  const RewardResponse({
    required this.rewardId,
    required this.gymId,
    required this.title,
    required this.pointCost,
    this.imageUrl,
    this.priceLabel,
    required this.isActive,
    required this.createdAt,
  });

  factory RewardResponse.fromJson(Map<String, dynamic> json) =>
      _$RewardResponseFromJson(json);

  Map<String, dynamic> toJson() => _$RewardResponseToJson(this);
}
