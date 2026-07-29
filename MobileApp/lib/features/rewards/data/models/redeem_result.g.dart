// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'redeem_result.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RedeemResult _$RedeemResultFromJson(Map<String, dynamic> json) => RedeemResult(
  redemptionId: json['redemption_id'] as String,
  memberId: json['member_id'] as String,
  rewardId: json['reward_id'] as String,
  gymId: json['gym_id'] as String,
  pointCost: (json['point_cost'] as num).toInt(),
  requestedAt: json['requested_at'] as String,
  status: redemptionStatusFromJson(json['status']),
  pointsBalanceAfter: (json['points_balance_after'] as num).toInt(),
  resolvedAt: json['resolved_at'] as String?,
);
