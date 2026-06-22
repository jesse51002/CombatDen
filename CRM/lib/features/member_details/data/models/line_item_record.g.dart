// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'line_item_record.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LineItemRecord _$LineItemRecordFromJson(Map<String, dynamic> json) =>
    LineItemRecord(
      lineItemId: json['line_item_id'] as String,
      itemType: LineItemType.fromJson(json['item_type'] as String),
      name: json['name'] as String,
      amount: (json['amount'] as num).toInt(),
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      stripeProductId: json['stripe_product_id'] as String?,
      itemId: json['item_id'] as String?,
      ownerMemberId: json['owner_member_id'] as String?,
      ownerFirstName: json['owner_first_name'] as String?,
      ownerLastName: json['owner_last_name'] as String?,
    );
