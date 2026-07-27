import 'package:json_annotation/json_annotation.dart';

part 'reward_item.g.dart';

/// A single reward in a gym's ACTIVE catalog — what a member can spend earned
/// points on.
///
/// Mirrors `RewardResponse` in
/// `FastApiBackend/src/rewards/schema/rewards_schema.py`
/// (`GET /api/v1/member/gyms/{gid}/members/{mid}/rewards`). [imageUrl] /
/// [priceLabel] are never null — both `gym_rewards` columns are NOT NULL
/// (writers fill the platform default image / a required value badge). The
/// member surface only ever returns active rewards, so [isActive] is always
/// true here. [createdAt] is kept as the backend's raw ISO datetime string.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class RewardItem {
  final String rewardId;
  final String gymId;
  final String title;
  final int pointCost;
  final String imageUrl;
  final String priceLabel;
  final bool isActive;
  final String createdAt;

  const RewardItem({
    required this.rewardId,
    required this.gymId,
    required this.title,
    required this.pointCost,
    required this.imageUrl,
    required this.priceLabel,
    required this.isActive,
    required this.createdAt,
  });

  factory RewardItem.fromJson(Map<String, dynamic> json) =>
      _$RewardItemFromJson(json);
}
