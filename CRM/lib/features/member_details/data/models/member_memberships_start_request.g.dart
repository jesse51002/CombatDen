// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'member_memberships_start_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Map<String, dynamic> _$MemberMembershipsStartRequestToJson(
  MemberMembershipsStartRequest instance,
) => <String, dynamic>{
  'stringify': instance.stringify,
  'hash_code': instance.hashCode,
  'payer_member_id': instance.payerMemberId,
  'gym_id': instance.gymId,
  'prorate': instance.prorate,
  'paid_with_cash': instance.paidWithCash,
  'idempotency_key': instance.idempotencyKey,
  'memberships': instance.memberships.map((e) => e.toJson()).toList(),
  'props': instance.props,
};
