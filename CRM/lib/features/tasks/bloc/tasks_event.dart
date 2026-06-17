import 'package:equatable/equatable.dart';

sealed class TasksEvent extends Equatable {
  const TasksEvent();

  @override
  List<Object?> get props => [];
}

/// Load all ongoing tasks for the gym (no polling).
class TasksOngoingRequested extends TasksEvent {
  final String gymId;
  const TasksOngoingRequested(this.gymId);

  @override
  List<Object?> get props => [gymId];
}

/// Begin polling a specific task until it reaches a
/// terminal state (completed / failed).
class TaskPollingStarted extends TasksEvent {
  final String taskId;
  final String gymId;
  final String? planName;
  final int? targetPriceCents;

  const TaskPollingStarted({
    required this.taskId,
    required this.gymId,
    this.planName,
    this.targetPriceCents,
  });

  @override
  List<Object?> get props => [taskId, gymId, planName, targetPriceCents];
}

// Internal — do not dispatch from outside TasksBloc.
class TaskPollTick extends TasksEvent {
  final String taskId;
  final String gymId;
  const TaskPollTick({required this.taskId, required this.gymId});

  @override
  List<Object?> get props => [taskId, gymId];
}

/// Stop polling the current task and clear the progress state.
class TaskPollingCancelled extends TasksEvent {
  const TaskPollingCancelled();
}
