import 'package:equatable/equatable.dart';

import 'package:crm/features/tasks/data/models/task_response.dart';

sealed class TasksState extends Equatable {
  const TasksState();

  @override
  List<Object?> get props => [];
}

class TasksInitial extends TasksState {
  const TasksInitial();
}

/// Ongoing-tasks loaded (used for Feature 1 — in-task set).
class TasksLoaded extends TasksState {
  /// All item IDs (old_item_id / new_item_id) that belong to a
  /// pending or running task item across all ongoing tasks.
  final Set<String> inTaskItemIds;

  const TasksLoaded({required this.inTaskItemIds});

  @override
  List<Object?> get props => [inTaskItemIds];
}

class TasksError extends TasksState {
  final String message;
  const TasksError(this.message);

  @override
  List<Object?> get props => [message];
}

/// A specific task is being polled for progress.
class TaskPolling extends TasksState {
  final TaskResponse task;

  /// Item IDs still in flight across all known tasks (includes
  /// the polled task so the guard stays live during the run).
  final Set<String> inTaskItemIds;

  const TaskPolling({
    required this.task,
    required this.inTaskItemIds,
  });

  int get completed => task.completedCount;
  int get total => task.totalCount;

  /// Progress 0.0–1.0; null when total is 0 (indeterminate).
  double? get progress =>
      total > 0 ? completed / total : null;

  @override
  List<Object?> get props => [task, inTaskItemIds];
}

/// Polling finished — terminal state.
class TaskPollingDone extends TasksState {
  final TaskResponse task;
  final Set<String> inTaskItemIds;

  const TaskPollingDone({
    required this.task,
    required this.inTaskItemIds,
  });

  @override
  List<Object?> get props => [task, inTaskItemIds];
}
