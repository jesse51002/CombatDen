// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'member_memberships_start_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Map<String, dynamic> _$MemberMembershipsStartRequestToJson(
  MemberMembershipsStartRequest instance,
) => <String, dynamic>{
  'payer_member_id': instance.payerMemberId,
  'gym_id': instance.gymId,
  'prorate': instance.prorate,
  'paid_with_cash': instance.paidWithCash,
  'payment': instance.payment?.toJson(),
  'idempotency_key': instance.idempotencyKey,
  'memberships': instance.memberships.map((e) => e.toJson()).toList(),
};
