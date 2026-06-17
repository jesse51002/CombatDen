"""Pydantic models for the tasks domain.

A task is one staff-initiated background operation (the request returns the
``task_id``; the CRM polls). Its per-membership work units are the items —
each tracked with status, attempts, error, the typed op parameters, and the
old→new membership-row linkage the operation produced.
"""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel
from schema.task import TaskStatus, TaskType

import src.shared.db_schema_path  # noqa: F401


class TaskItemCreate(BaseModel):
    """One work unit to enqueue when creating a task (backend-internal)."""

    member_id: UUID
    old_item_id: UUID | None = None
    target_price_id: UUID | None = None
    prorate: bool | None = None


class TaskItemResponse(BaseModel):
    """One task item — also the record handed to the item's executor."""

    task_item_id: UUID
    task_id: UUID
    gym_id: UUID
    member_id: UUID
    status: TaskStatus
    attempt_count: int
    error_message: str | None = None
    old_item_id: UUID | None = None
    new_item_id: UUID | None = None
    target_price_id: UUID | None = None
    prorate: bool | None = None
    created_at: datetime
    started_at: datetime | None = None
    finished_at: datetime | None = None


class TaskResponse(BaseModel):
    """A task with its items — the CRM's polling payload."""

    task_id: UUID
    gym_id: UUID
    task_type: TaskType
    status: TaskStatus
    created_at: datetime
    started_at: datetime | None = None
    finished_at: datetime | None = None
    items: list[TaskItemResponse]
