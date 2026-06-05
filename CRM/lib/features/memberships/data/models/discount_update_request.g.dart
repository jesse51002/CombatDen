// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'discount_update_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Map<String, dynamic> _$DiscountUpdateDataToJson(DiscountUpdateData instance) =>
    <String, dynamic>{
      'discount_name': ?instance.discountName,
      'percentage_off': ?instance.percentageOff,
      'dollar_off': ?instance.dollarOff,
      'discount_mode': ?instance.discountMode,
      'duration_amount': ?instance.durationAmount,
      'duration_unit': ?instance.durationUnit,
      'end_date': ?DiscountUpdateData._dateToJson(instance.endDate),
    };

Map<String, dynamic> _$DiscountUpdateRequestToJson(
  DiscountUpdateRequest instance,
) => <String, dynamic>{
  'discount_id': instance.discountId,
  'gym_id': instance.gymId,
  'data': instance.data.toJson(),
};
