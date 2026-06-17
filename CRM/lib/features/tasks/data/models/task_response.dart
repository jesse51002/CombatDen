import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:crm/features/tasks/data/models/task_enums.dart';
import 'package:crm/features/tasks/data/models/task_item.dart';

part 'task_response.g.dart';

/// A background task with its line items.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class TaskResponse extends Equatable {
  final String taskId;
  final String gymId;
  @JsonKey(fromJson: TaskType.fromJson)
  final TaskType taskType;
  @JsonKey(fromJson: TaskStatus.fromJson)
  final TaskStatus status;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  @JsonKey(defaultValue: <TaskItem>[])
  final List<TaskItem> items;

  const TaskResponse({
    required this.taskId,
    required this.gymId,
    required this.taskType,
    required this.status,
    required this.createdAt,
    this.startedAt,
    this.finishedAt,
    this.items = const [],
  });

  factory TaskResponse.fromJson(Map<String, dynamic> json) =>
      _$TaskResponseFromJson(json);

  /// Whether the task has reached a terminal state.
  bool get isTerminal =>
      status == TaskStatus.completed || status == TaskStatus.failed;

  /// The set of item IDs (old_item_id + new_item_id) that are
  /// currently in flight (pending or running).
  Set<String> get inFlightItemIds {
    final ids = <String>{};
    for (final item in items) {
      if (item.status == TaskStatus.pending ||
          item.status == TaskStatus.running) {
        if (item.oldItemId != null) ids.add(item.oldItemId!);
        if (item.newItemId != null) ids.add(item.newItemId!);
      }
    }
    return ids;
  }

  int get completedCount =>
      items.where((i) => i.status == TaskStatus.completed).length;

  int get totalCount => items.length;

  @override
  List<Object?> get props => [
        taskId,
        gymId,
        taskType,
        status,
        createdAt,
        startedAt,
        finishedAt,
        items,
      ];
}
