// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pending_redemption_card.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PendingRedemptionCard _$PendingRedemptionCardFromJson(
  Map<String, dynamic> json,
) => PendingRedemptionCard(
  redemptionId: json['redemption_id'] as String,
  rewardId: json['reward_id'] as String,
  title: json['title'] as String,
  priceLabel: json['price_label'] as String,
  imageUrl: json['image_url'] as String,
  pointCost: (json['point_cost'] as num).toInt(),
  requestedAt: json['requested_at'] as String,
);
