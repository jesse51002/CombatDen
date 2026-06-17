import 'dart:async';
import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:crm/features/tasks/bloc/tasks_event.dart';
import 'package:crm/features/tasks/bloc/tasks_state.dart';
import 'package:crm/features/tasks/data/models/task_response.dart';
import 'package:crm/features/tasks/data/repositories/tasks_repository.dart';

/// Manages the task list and optional single-task polling.
///
/// Typical flow:
/// 1. [TasksOngoingRequested] — loads all ongoing tasks → [TasksLoaded]
///    (the in-task guard set is derived from the items).
/// 2. [TaskPollingStarted] — kicks off a periodic Timer to poll a
///    specific task → [TaskPolling] on each tick, [TaskPollingDone] on
///    terminal, [TasksError] on persistent failure.
/// 3. [TaskPollingCancelled] — stops the timer and resets to [TasksInitial].
class TasksBloc extends Bloc<TasksEvent, TasksState> {
  final TasksRepository _repository;
  Timer? _pollTimer;

  /// Polling interval. Short enough to feel responsive;
  /// long enough not to spam the backend.
  static const Duration _pollInterval = Duration(seconds: 3);

  TasksBloc({required TasksRepository repository})
      : _repository = repository,
        super(const TasksInitial()) {
    on<TasksOngoingRequested>(_onOngoingRequested);
    on<TaskPollingStarted>(_onPollingStarted);
    on<TaskPollTick>(_onPollTick);
    on<TaskPollingCancelled>(_onPollingCancelled);
  }

  Future<void> _onOngoingRequested(
    TasksOngoingRequested event,
    Emitter<TasksState> emit,
  ) async {
    try {
      final tasks = await _repository.getOngoingTasks(event.gymId);
      emit(TasksLoaded(inTaskItemIds: _buildInTaskSet(tasks)));
    } catch (e, s) {
      log('Failed to load ongoing tasks', error: e, stackTrace: s);
      emit(TasksError(e.toString()));
    }
  }

  Future<void> _onPollingStarted(
    TaskPollingStarted event,
    Emitter<TasksState> emit,
  ) async {
    _cancelTimer();
    // Immediate first fetch.
    try {
      final task = await _repository.getTask(
        event.taskId,
        event.gymId,
      );
      final inFlight = task.inFlightItemIds;
      if (task.isTerminal) {
        emit(TaskPollingDone(task: task, inTaskItemIds: inFlight));
        return;
      }
      emit(TaskPolling(task: task, inTaskItemIds: inFlight));
    } catch (e, s) {
      log('Task poll failed', error: e, stackTrace: s);
      emit(TasksError(e.toString()));
      return;
    }
    // Schedule ticks.
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (!isClosed) {
        add(TaskPollTick(taskId: event.taskId, gymId: event.gymId));
      }
    });
  }

  Future<void> _onPollTick(
    TaskPollTick event,
    Emitter<TasksState> emit,
  ) async {
    try {
      final task = await _repository.getTask(
        event.taskId,
        event.gymId,
      );
      final inFlight = task.inFlightItemIds;
      if (task.isTerminal) {
        _cancelTimer();
        emit(TaskPollingDone(task: task, inTaskItemIds: inFlight));
        return;
      }
      emit(TaskPolling(task: task, inTaskItemIds: inFlight));
    } catch (e, s) {
      log('Task poll tick failed', error: e, stackTrace: s);
      // Keep polling on transient errors — only cancel on terminal.
    }
  }

  void _onPollingCancelled(
    TaskPollingCancelled event,
    Emitter<TasksState> emit,
  ) {
    _cancelTimer();
    emit(const TasksInitial());
  }

  void _cancelTimer() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Set<String> _buildInTaskSet(List<TaskResponse> tasks) {
    final ids = <String>{};
    for (final t in tasks) {
      ids.addAll(t.inFlightItemIds);
    }
    return ids;
  }

  @override
  Future<void> close() {
    _cancelTimer();
    return super.close();
  }
}
