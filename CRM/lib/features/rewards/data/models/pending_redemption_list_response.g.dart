// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pending_redemption_list_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PendingRedemptionListResponse _$PendingRedemptionListResponseFromJson(
  Map<String, dynamic> json,
) => PendingRedemptionListResponse(
  items: (json['items'] as List<dynamic>)
      .map((e) => PendingRedemptionItem.fromJson(e as Map<String, dynamic>))
      .toList(),
  total: (json['total'] as num).toInt(),
);
