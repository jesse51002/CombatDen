// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'member_memberships_start_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Map<String, dynamic> _$MemberMembershipsStartItemToJson(
  MemberMembershipsStartItem instance,
) => <String, dynamic>{
  'member_id': instance.memberId,
  'price_id': instance.priceId,
  'quantity': instance.quantity,
  'discount_ids': instance.discountIds,
  'custom_discounts': instance.customDiscounts.map((e) => e.toJson()).toList(),
};
