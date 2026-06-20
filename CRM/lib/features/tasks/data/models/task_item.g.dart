// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'task_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TaskItem _$TaskItemFromJson(Map<String, dynamic> json) => TaskItem(
  taskItemId: json['task_item_id'] as String,
  taskId: json['task_id'] as String,
  gymId: json['gym_id'] as String,
  memberId: json['member_id'] as String,
  status: TaskStatus.fromJson(json['status'] as String),
  attemptCount: (json['attempt_count'] as num).toInt(),
  errorMessage: json['error_message'] as String?,
  oldItemId: json['old_item_id'] as String?,
  newItemId: json['new_item_id'] as String?,
  targetPriceId: json['target_price_id'] as String?,
  prorationBehavior: TaskItem._prorationOrNull(json['proration_behavior']),
  createdAt: DateTime.parse(json['created_at'] as String),
  startedAt: json['started_at'] == null
      ? null
      : DateTime.parse(json['started_at'] as String),
  finishedAt: json['finished_at'] == null
      ? null
      : DateTime.parse(json['finished_at'] as String),
);
