// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pays_for_member.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PaysForMembership _$PaysForMembershipFromJson(Map<String, dynamic> json) =>
    PaysForMembership(
      itemId: json['item_id'] as String,
      planName: json['plan_name'] as String,
    );

PaysForMember _$PaysForMemberFromJson(Map<String, dynamic> json) =>
    PaysForMember(
      memberId: json['member_id'] as String,
      firstName: json['first_name'] as String,
      lastName: json['last_name'] as String,
      photoUrl: json['photo_url'] as String?,
      memberships:
          (json['memberships'] as List<dynamic>?)
              ?.map(
                (e) => PaysForMembership.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
    );
