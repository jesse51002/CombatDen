import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/member_details/data/models/proration_behavior.dart';
import 'package:crm/features/tasks/data/models/task_enums.dart';

part 'task_item.g.dart';

/// One item (one member's reprice) inside a background task.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class TaskItem extends Equatable {
  final String taskItemId;
  final String taskId;
  final String gymId;
  final String memberId;
  @JsonKey(fromJson: TaskStatus.fromJson)
  final TaskStatus status;
  final int attemptCount;
  final String? errorMessage;
  final String? oldItemId;
  final String? newItemId;
  final String? targetPriceId;
  @JsonKey(fromJson: _prorationOrNull)
  final ProrationBehavior? prorationBehavior;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  const TaskItem({
    required this.taskItemId,
    required this.taskId,
    required this.gymId,
    required this.memberId,
    required this.status,
    required this.attemptCount,
    this.errorMessage,
    this.oldItemId,
    this.newItemId,
    this.targetPriceId,
    this.prorationBehavior,
    required this.createdAt,
    this.startedAt,
    this.finishedAt,
  });

  factory TaskItem.fromJson(Map<String, dynamic> json) =>
      _$TaskItemFromJson(json);

  static ProrationBehavior? _prorationOrNull(Object? value) =>
      value == null
          ? null
          : ProrationBehavior.fromJson(value as String);

  @override
  List<Object?> get props => [
        taskItemId,
        taskId,
        gymId,
        memberId,
        status,
        attemptCount,
        errorMessage,
        oldItemId,
        newItemId,
        targetPriceId,
        prorationBehavior,
        createdAt,
        startedAt,
        finishedAt,
      ];
}
