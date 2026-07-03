// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pending_redemption_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PendingRedemptionItem _$PendingRedemptionItemFromJson(
  Map<String, dynamic> json,
) => PendingRedemptionItem(
  redemptionId: json['redemption_id'] as String,
  memberId: json['member_id'] as String,
  memberName: json['member_name'] as String,
  rewardTitle: json['reward_title'] as String,
  rewardImageUrl: json['reward_image_url'] as String?,
  pointCost: (json['point_cost'] as num).toInt(),
  redeemedAt: DateTime.parse(json['redeemed_at'] as String),
);

Map<String, dynamic> _$PendingRedemptionItemToJson(
  PendingRedemptionItem instance,
) => <String, dynamic>{
  'redemption_id': instance.redemptionId,
  'member_id': instance.memberId,
  'member_name': instance.memberName,
  'reward_title': instance.rewardTitle,
  'reward_image_url': instance.rewardImageUrl,
  'point_cost': instance.pointCost,
  'redeemed_at': instance.redeemedAt.toIso8601String(),
};
