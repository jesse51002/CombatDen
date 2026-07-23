// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'member_identity.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MemberIdentity _$MemberIdentityFromJson(Map<String, dynamic> json) =>
    MemberIdentity(
      memberId: json['member_id'] as String,
      gymId: json['gym_id'] as String,
      gymName: json['gym_name'] as String,
      firstName: json['first_name'] as String,
      lastName: json['last_name'] as String,
      gymLogoUrl: json['gym_logo_url'] as String?,
      photoUrl: json['photo_url'] as String?,
    );

Map<String, dynamic> _$MemberIdentityToJson(MemberIdentity instance) =>
    <String, dynamic>{
      'member_id': instance.memberId,
      'gym_id': instance.gymId,
      'gym_name': instance.gymName,
      'gym_logo_url': instance.gymLogoUrl,
      'first_name': instance.firstName,
      'last_name': instance.lastName,
      'photo_url': instance.photoUrl,
    };
