// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'member_video_rec.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MemberVideoRec _$MemberVideoRecFromJson(Map<String, dynamic> json) =>
    MemberVideoRec(
      recId: json['rec_id'] as String,
      category: videoGenreFromJson(json['category']),
      video: GymVideoCard.fromJson(json['video'] as Map<String, dynamic>),
    );
