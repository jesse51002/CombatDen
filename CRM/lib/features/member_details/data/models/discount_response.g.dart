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
      value: DiscountValue.fromJson(json['value'] as Map<String, dynamic>),
      isDeleted: json['is_deleted'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
