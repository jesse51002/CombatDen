// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'member_memberships_start_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MemberMembershipsStartResponse _$MemberMembershipsStartResponseFromJson(
  Map<String, dynamic> json,
) => MemberMembershipsStartResponse(
  results:
      (json['results'] as List<dynamic>?)
          ?.map(
            (e) => MemberMembershipsStartResultItem.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList() ??
      [],
  chargeCount: (json['charge_count'] as num).toInt(),
  multipleCharges: json['multiple_charges'] as bool,
);
