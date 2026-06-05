// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'discount_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DiscountResponse _$DiscountResponseFromJson(Map<String, dynamic> json) =>
    DiscountResponse(
      discountId: json['discount_id'] as String,
      gymId: json['gym_id'] as String,
      discountName: json['discount_name'] as String,
      discountType: DiscountType.fromJson(json['discount_type'] as String),
      valueId: json['value_id'] as String,
      percentageOff: (json['percentage_off'] as num?)?.toDouble(),
      dollarOff: (json['dollar_off'] as num?)?.toInt(),
      discountMode: DiscountMode.fromJson(json['discount_mode'] as String),
      durationAmount: (json['duration_amount'] as num?)?.toInt(),
      durationUnit: DiscountResponse._durationUnitOrNull(json['duration_unit']),
      endDate: json['end_date'] == null
          ? null
          : DateTime.parse(json['end_date'] as String),
      isDeleted: json['is_deleted'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
