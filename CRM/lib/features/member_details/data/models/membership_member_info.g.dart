// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'membership_member_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MembershipMemberInfo _$MembershipMemberInfoFromJson(
  Map<String, dynamic> json,
) => MembershipMemberInfo(
  itemId: json['item_id'] as String,
  endDate: json['end_date'] == null
      ? null
      : DateTime.parse(json['end_date'] as String),
  cancelDate: json['cancel_date'] == null
      ? null
      : DateTime.parse(json['cancel_date'] as String),
  onOutdatedPrice: json['on_outdated_price'] as bool? ?? false,
);
