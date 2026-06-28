// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pending_redemption_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PendingRedemptionItem _$PendingRedemptionItemFromJson(
  Map<String, dynamic> json,
) => PendingRedemptionItem(
  redemptionId: json['redemptionId'] as String,
  memberId: json['memberId'] as String,
  memberName: json['memberName'] as String,
  rewardTitle: json['rewardTitle'] as String,
  rewardImageUrl: json['rewardImageUrl'] as String?,
  pointCost: (json['pointCost'] as num).toInt(),
  redeemedAt: DateTime.parse(json['redeemedAt'] as String),
);

Map<String, dynamic> _$PendingRedemptionItemToJson(
  PendingRedemptionItem instance,
) => <String, dynamic>{
  'redemptionId': instance.redemptionId,
  'memberId': instance.memberId,
  'memberName': instance.memberName,
  'rewardTitle': instance.rewardTitle,
  'rewardImageUrl': instance.rewardImageUrl,
  'pointCost': instance.pointCost,
  'redeemedAt': instance.redeemedAt.toIso8601String(),
};
