// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'membership_plan_create_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Map<String, dynamic> _$MembershipPlanCreateRequestToJson(
  MembershipPlanCreateRequest instance,
) => <String, dynamic>{
  'gym_id': instance.gymId,
  'plan_name': instance.planName,
  'plan_type': instance.planType,
  'class_count': instance.classCount,
  'duration_amount': instance.durationAmount,
  'duration_unit': instance.durationUnit,
  'is_public': instance.isPublic,
  'price': instance.price,
  'waiver_ids': instance.waiverIds,
  'linked_discount_enabled': instance.linkedDiscountEnabled,
  'linked_discount_prices': instance.linkedDiscountPrices,
};
