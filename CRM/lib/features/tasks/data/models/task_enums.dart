import 'package:json_annotation/json_annotation.dart';

/// Task status — the lifecycle of a background task.
/// [unknown] catches any future backend value the UI hasn't seen.
@JsonEnum(valueField: 'value')
enum TaskStatus {
  pending('pending', 'Pending'),
  running('running', 'Running'),
  completed('completed', 'Completed'),
  failed('failed', 'Failed'),
  unknown('unknown', 'Unknown');

  const TaskStatus(this.value, this.displayLabel);

  final String value;
  final String displayLabel;

  static TaskStatus fromJson(String value) =>
      TaskStatus.values.firstWhere(
        (v) => v.value == value,
        orElse: () => TaskStatus.unknown,
      );

  String toJson() => value;
}

/// Task type — the operation a task performs.
/// [unknown] is the forward-compat fallback.
@JsonEnum(valueField: 'value')
enum TaskType {
  membershipReprice('membership_reprice', 'Membership Reprice'),
  unknown('unknown', 'Unknown');

  const TaskType(this.value, this.displayLabel);

  final String value;
  final String displayLabel;

  static TaskType fromJson(String value) =>
      TaskType.values.firstWhere(
        (v) => v.value == value,
        orElse: () => TaskType.unknown,
      );

  String toJson() => value;
}
