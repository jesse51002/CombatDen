// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'membership_plan_update_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Map<String, dynamic> _$MembershipPlanUpdateDataToJson(
  MembershipPlanUpdateData instance,
) => <String, dynamic>{
  'plan_name': ?instance.planName,
  'class_count': ?instance.classCount,
  'duration_amount': ?instance.durationAmount,
  'duration_unit': ?instance.durationUnit?.toJson(),
  'is_public': ?instance.isPublic,
  'waiver_ids': ?instance.waiverIds,
  'linked_discount_enabled': ?instance.linkedDiscountEnabled,
  'linked_discount_values': ?instance.linkedDiscountValues
      ?.map((e) => e.toJson())
      .toList(),
};

Map<String, dynamic> _$MembershipPlanUpdateRequestToJson(
  MembershipPlanUpdateRequest instance,
) => <String, dynamic>{
  'plan_id': instance.planId,
  'gym_id': instance.gymId,
  'data': instance.data.toJson(),
};
