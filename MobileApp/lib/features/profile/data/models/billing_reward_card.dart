import 'package:json_annotation/json_annotation.dart';

part 'billing_reward_card.g.dart';

/// A recently redeemed reward.
///
/// Mirrors `BillingRewardCard` in
/// `FastApiBackend/src/members/schema/members_billing_schema.py`.
/// [priceLabel] / [imageUrl] are never null (both `gym_rewards` columns are
/// NOT NULL).
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class BillingRewardCard {
  final String rewardId;
  final String title;
  final String priceLabel;
  final String imageUrl;
  final int pointCost;

  const BillingRewardCard({
    required this.rewardId,
    required this.title,
    required this.priceLabel,
    required this.imageUrl,
    required this.pointCost,
  });

  factory BillingRewardCard.fromJson(Map<String, dynamic> json) =>
      _$BillingRewardCardFromJson(json);
}
