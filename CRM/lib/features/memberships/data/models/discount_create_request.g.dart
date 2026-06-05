// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'discount_create_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Map<String, dynamic> _$DiscountCreateRequestToJson(
  DiscountCreateRequest instance,
) => <String, dynamic>{
  'gym_id': instance.gymId,
  'discount_name': instance.discountName,
  'discount_type': instance.discountType,
  'percentage_off': ?instance.percentageOff,
  'dollar_off': ?instance.dollarOff,
  'discount_mode': instance.discountMode,
  'duration_amount': ?instance.durationAmount,
  'duration_unit': ?instance.durationUnit,
  'end_date': ?DiscountCreateRequest._dateToJson(instance.endDate),
};
