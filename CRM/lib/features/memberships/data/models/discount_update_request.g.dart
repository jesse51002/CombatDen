// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'discount_update_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Map<String, dynamic> _$DiscountUpdateIdentityToJson(
  DiscountUpdateIdentity instance,
) => <String, dynamic>{'discount_name': ?instance.discountName};

Map<String, dynamic> _$DiscountUpdateValuesToJson(
  DiscountUpdateValues instance,
) => <String, dynamic>{
  'percentage_off': ?instance.percentageOff,
  'dollar_off': ?instance.dollarOff,
  'discount_mode': ?instance.discountMode,
  'duration_amount': ?instance.durationAmount,
  'duration_unit': ?instance.durationUnit,
  'end_date': ?DiscountUpdateValues._dateToJson(instance.endDate),
};

Map<String, dynamic> _$DiscountUpdateRequestToJson(
  DiscountUpdateRequest instance,
) => <String, dynamic>{
  'discount_id': instance.discountId,
  'gym_id': instance.gymId,
  'identity': ?instance.identity?.toJson(),
  'values': ?instance.values?.toJson(),
};
