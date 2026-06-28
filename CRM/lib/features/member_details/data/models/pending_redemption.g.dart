// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pending_redemption.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PendingRedemption _$PendingRedemptionFromJson(Map<String, dynamic> json) =>
    PendingRedemption(
      redemptionId: json['redemption_id'] as String,
      rewardId: json['reward_id'] as String,
      title: json['title'] as String,
      amountOff: json['amount_off'] as String?,
      imageUrl: json['image_url'] as String?,
      pointCost: (json['point_cost'] as num).toInt(),
      redeemedAt: DateTime.parse(json['redeemed_at'] as String),
    );
