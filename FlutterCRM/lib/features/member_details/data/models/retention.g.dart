// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'retention.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Retention _$RetentionFromJson(Map<String, dynamic> json) => Retention(
  lastClass: json['last_class'] == null
      ? null
      : DateTime.parse(json['last_class'] as String),
  classStreakWeeks: (json['class_streak_weeks'] as num).toInt(),
  pointsBalance: (json['points_balance'] as num).toInt(),
  videosWatched: (json['videos_watched'] as num).toInt(),
);
