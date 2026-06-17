"""StaleTaskSweep — re-run tracked tasks whose in-process execution died.

A tracked task (``src/tasks/``) runs its items in a fire-and-forget background
run right after the request returns. If the process dies mid-run, the task is
left ``pending`` (never started) or ``running`` with a stale claim. This sweep —
one step of the twice-daily reconciler run — re-runs every unfinished task; the
executor's atomic claims decide what is actually runnable (a ``pending`` item,
or a ``running`` claim older than ``settings.task_stale_running_seconds`` left by a dead
process), so a still-live in-process run is never disturbed.

The recovery loop lives here, in the reconciler — the tasks engine owns only
how to run ONE task (``TasksExecutor.run_task``) and how to read its data
(``TasksQueries``); the scheduling of recovery is the reconciler's concern.
Genuinely ``failed`` tasks (out of attempts) are NOT re-run here — they are no
longer "unfinished"; the payment-push sweep converges whatever they left.
"""

import logging

from src.reconciler.service.reconciler.reconciler_result import SweepResult
from src.shared.database import DirectDatabasePool
from src.tasks.service.tasks_executor import TasksExecutor
from src.tasks.service.tasks_queries import TasksQueries

logger = logging.getLogger(__name__)

SWEEP_NAME = "stale_task_recovery"


class StaleTaskSweep:
    """Re-run every unfinished tracked task; skip whatever a live run owns."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        tasks_executor: TasksExecutor,
    ) -> None:
        self._tasks_executor = tasks_executor
        self._queries = TasksQueries(db_pool)

    async def run(self) -> SweepResult:
        """Re-run each unfinished task; a per-task failure never aborts the sweep."""
        task_ids = await self._queries.list_unfinished_task_ids()
        result = SweepResult(name=SWEEP_NAME, processed=len(task_ids))
        for task_id in task_ids:
            try:
                await self._tasks_executor.run_task(task_id)
                result.changed += 1
            except Exception:
                logger.error(
                    "Stale-task recovery run failed: task_id=%s",
                    task_id,
                    exc_info=True,
                )
                result.errors += 1
        logger.info(
            "Stale-task recovery: processed=%d reran=%d errors=%d",
            result.processed,
            result.changed,
            result.errors,
        )
        return result
