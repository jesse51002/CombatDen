// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'billing_retention.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BillingRetention _$BillingRetentionFromJson(Map<String, dynamic> json) =>
    BillingRetention(
      classStreakWeeks: (json['class_streak_weeks'] as num).toInt(),
      pointsBalance: (json['points_balance'] as num).toInt(),
      videosWatched: (json['videos_watched'] as num).toInt(),
      lastClass: json['last_class'] as String?,
      currentWeekAttendedWeekdays:
          (json['current_week_attended_weekdays'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          [],
    );
