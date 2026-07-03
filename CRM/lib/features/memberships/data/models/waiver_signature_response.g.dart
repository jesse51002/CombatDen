// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'waiver_signature_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

WaiverSignatureResponse _$WaiverSignatureResponseFromJson(
  Map<String, dynamic> json,
) => WaiverSignatureResponse(
  signatureId: json['signature_id'] as String,
  waiverId: json['waiver_id'] as String,
  waiverVersionId: json['waiver_version_id'] as String,
  memberId: json['member_id'] as String,
  gymId: json['gym_id'] as String,
  signedAt: DateTime.parse(json['signed_at'] as String),
  signerName: json['signer_name'] as String,
  signatureType: json['signature_type'] as String,
);
