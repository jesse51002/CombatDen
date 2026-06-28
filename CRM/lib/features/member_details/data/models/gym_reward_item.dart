import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'gym_reward_item.g.dart';

/// One active gym reward from `GET /api/v1/rewards/`.
///
/// Used by the redeem-for-member reward picker dialog.
/// Mirrors `RewardResponse` from
/// `FastApiBackend/src/rewards/schema/rewards_schema.py`.
@JsonSerializable(
  fieldRename: FieldRename.snake,
  createToJson: false,
)
class GymRewardItem extends Equatable {
  final String rewardId;
  final String title;
  final int pointCost;
  final String? priceLabel;
  final String? imageUrl;
  final bool isActive;

  const GymRewardItem({
    required this.rewardId,
    required this.title,
    required this.pointCost,
    this.priceLabel,
    this.imageUrl,
    required this.isActive,
  });

  factory GymRewardItem.fromJson(
    Map<String, dynamic> json,
  ) =>
      _$GymRewardItemFromJson(json);

  @override
  List<Object?> get props => [
        rewardId,
        title,
        pointCost,
        priceLabel,
        imageUrl,
        isActive,
      ];
}
