from enum import StrEnum


class TaskType(StrEnum):
    """Mirrors the Postgres `task_type` enum.

    What operation a task performs. Each value has a registered executor in
    the backend (`src/tasks/service/tasks_executor.py`).
    """

    membership_reprice = "membership_reprice"


class TaskStatus(StrEnum):
    """Mirrors the Postgres `task_status` enum.

    Lifecycle of a task and of each of its items. Items: `pending` = queued
    (also the state a retryable failure returns to), `running` = claimed by an
    executor, then `completed` or `failed` (terminal, after max attempts).
    Tasks: `pending` until the first item is claimed, `running` while items
    are in flight, then `completed` (all items completed) or `failed` (any
    item failed).
    """

    pending = "pending"
    running = "running"
    completed = "completed"
    failed = "failed"
