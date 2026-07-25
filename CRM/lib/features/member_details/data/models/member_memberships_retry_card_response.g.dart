// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'member_memberships_retry_card_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MemberMembershipsRetryCardResponse _$MemberMembershipsRetryCardResponseFromJson(
  Map<String, dynamic> json,
) => MemberMembershipsRetryCardResponse(
  itemId: json['item_id'] as String,
  memberId: json['member_id'] as String,
  status: MemberMembershipsRetryCardStatus.fromJson(json['status'] as String),
  declineReason: json['decline_reason'] as String?,
);
