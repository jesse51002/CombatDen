"""Runs tasks: claims items, dispatches to the task_type's handler, retries.

The executor owns the task/item state machine; the operation logic lives in
each domain's registered handler (e.g. the memberships reprice handler). Per
item it mirrors the reconciler's bulk-sync retry: claim → execute → on failure
record the error, release to 'pending', wait, re-claim — up to
``settings.task_item_max_attempts`` attempts (never sleeping after the last),
then mark the item 'failed'. The executor never reverts anything — each operation
handles its own failure (the DB-first verify-or-revert contract), so a failed
item is purely a record of the error.
"""

import asyncio
import logging
from typing import ClassVar, Protocol
from uuid import UUID

from schema.task import TaskStatus, TaskType

import src.shared.db_schema_path  # noqa: F401
from src.core.config import settings
from src.shared.database import DirectDatabasePool
from src.tasks.service.tasks_queries import TasksQueries
from src.tasks.tasks_schema import TaskItemResponse

logger = logging.getLogger(__name__)


class TaskItemHandler(Protocol):
    """One task_type's per-item operation (registered in the DI container)."""

    async def execute_item(self, item: TaskItemResponse) -> None:
        """Execute one claimed item; raise on failure (the executor retries)."""
        ...


class TasksExecutor:
    """Claims and executes task items via the registered per-type handlers."""

    # Strong references to in-flight background runs (asyncio only keeps weak
    # ones); shared across DI factory instances on purpose.
    _background_runs: ClassVar[set[asyncio.Task]] = set()

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        handlers: dict[TaskType, TaskItemHandler],
    ) -> None:
        self._queries = TasksQueries(db_pool)
        self._handlers = handlers

    def start_in_background(self, task_id: UUID) -> None:
        """Fire-and-forget ``run_task`` — the request returns immediately.

        Holds a strong reference until the run finishes and logs any escape
        (run_task itself contains per-item failures; an exception here is an
        executor bug, not an item failure).
        """
        run = asyncio.create_task(self.run_task(task_id))
        self._background_runs.add(run)

        def _done(finished: asyncio.Task) -> None:
            self._background_runs.discard(finished)
            if not finished.cancelled() and finished.exception() is not None:
                logger.error(
                    "Background task run crashed: task_id=%s",
                    task_id,
                    exc_info=finished.exception(),
                )

        run.add_done_callback(_done)

    async def run_task(self, task_id: UUID) -> None:
        """Run every runnable item of a task, sequentially, then finalize.

        Safe to call concurrently (the in-process background run + the
        reconciler's stale-task recovery): the atomic claims guarantee each
        attempt has exactly one owner; an item another run owns is skipped.
        """
        items = await self._queries.get_items_for_task(task_id)
        if not items:
            logger.error("Task has no items: task_id=%s", task_id)
            return
        task = await self._queries.get_task(task_id, items[0].gym_id)
        if task is None:
            logger.error("Task not found: task_id=%s", task_id)
            return
        handler = self._handlers.get(task.task_type)
        if handler is None:
            logger.error(
                "No handler registered for task_type=%s (task_id=%s)",
                task.task_type,
                task_id,
            )
            return

        for item in items:
            await self._run_item(task_id, item, handler)
        await self._queries.finalize_task_status(task_id)

    # ── Private ────────────────────────────────────────────────

    async def _run_item(
        self,
        task_id: UUID,
        item: TaskItemResponse,
        handler: TaskItemHandler,
    ) -> None:
        """Claim-execute-retry one item until terminal or unclaimable."""
        while True:
            claimed = await self._claim(item)
            if claimed is None:
                return  # terminal, or another run owns it
            await self._queries.finalize_task_status(task_id)

            try:
                await handler.execute_item(claimed)
            except asyncio.CancelledError:
                # Shutdown mid-run: release so the sweep retries promptly
                # (without this the claim only expires via staleness).
                await self._queries.release_item_for_retry(
                    claimed.task_item_id,
                    "execution cancelled (shutdown)",
                )
                raise
            except Exception as exc:
                logger.error(
                    "Task item attempt %s/%s failed: task_item_id=%s",
                    claimed.attempt_count,
                    settings.task_item_max_attempts,
                    claimed.task_item_id,
                    exc_info=True,
                )
                if claimed.attempt_count >= settings.task_item_max_attempts:
                    await self._queries.fail_item(
                        claimed.task_item_id,
                        str(exc),
                    )
                    await self._queries.finalize_task_status(task_id)
                    return
                await self._queries.release_item_for_retry(
                    claimed.task_item_id,
                    str(exc),
                )
                await asyncio.sleep(settings.task_item_retry_delay_seconds)
                continue

            await self._queries.complete_item(claimed.task_item_id)
            await self._queries.finalize_task_status(task_id)
            return

    async def _claim(
        self,
        item: TaskItemResponse,
    ) -> TaskItemResponse | None:
        """Claim the item: pending normally, stale 'running' as recovery."""
        claimed = await self._queries.claim_item(item.task_item_id)
        if claimed is not None:
            return claimed
        if item.status == TaskStatus.running:
            return await self._queries.claim_stale_item(
                item.task_item_id,
                settings.task_stale_running_seconds,
            )
        return None
