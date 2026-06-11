// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'member_memberships_start_result_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MemberMembershipsStartResultItem _$MemberMembershipsStartResultItemFromJson(
  Map<String, dynamic> json,
) => MemberMembershipsStartResultItem(
  memberId: json['member_id'] as String,
  planId: json['plan_id'] as String,
  planType: PlanType.fromJson(json['plan_type'] as String),
  status: MemberMembershipsStartStatus.fromJson(json['status'] as String),
  itemId: json['item_id'] as String?,
  error: json['error'] as String?,
);
