// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'waiver_update_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Map<String, dynamic> _$WaiverUpdateDataToJson(WaiverUpdateData instance) =>
    <String, dynamic>{'name': ?instance.name, 'body': ?instance.body};

Map<String, dynamic> _$WaiverUpdateRequestToJson(
  WaiverUpdateRequest instance,
) => <String, dynamic>{
  'waiver_id': instance.waiverId,
  'gym_id': instance.gymId,
  'data': instance.data.toJson(),
};
