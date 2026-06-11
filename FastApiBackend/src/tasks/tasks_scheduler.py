"""APScheduler wiring for the tasks crash-recovery sweep.

Infrastructure glue (a function module, not a service): registers an interval
job that re-runs unfinished tasks whose in-process execution died (the normal
path is the request firing the run in the background). The app lifespan owns
the scheduler's start/stop; this module only adds the job — creating the
scheduler when the reconciler didn't already build one.
"""

import logging

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.interval import IntervalTrigger

from src.core.config import TASK_SWEEP_INTERVAL_MINUTES, settings
from src.core.dependencies import DependencyInjector

logger = logging.getLogger(__name__)

TASK_SWEEP_JOB_ID = "tasks_stale_sweep"


def register_task_sweep(
    container: DependencyInjector,
    scheduler: AsyncIOScheduler | None,
) -> AsyncIOScheduler | None:
    """Add the task sweep job (creating the scheduler if needed).

    Args:
        container: The DI container the job resolves ``TasksExecutor`` from.
        scheduler: An existing scheduler to share (the reconciler's), or None.

    Returns:
        The scheduler carrying the job — the one passed in, a new one when
        none existed, or the input unchanged when the sweep is disabled.
    """
    if not settings.tasks_sweep_enabled:
        return scheduler
    if scheduler is None:
        scheduler = AsyncIOScheduler(timezone="UTC")

    async def _run_sweep() -> None:
        try:
            await container.tasks_executor().sweep_stale()
        except Exception:
            logger.error("Task sweep run failed", exc_info=True)

    scheduler.add_job(
        _run_sweep,
        trigger=IntervalTrigger(minutes=TASK_SWEEP_INTERVAL_MINUTES),
        id=TASK_SWEEP_JOB_ID,
        max_instances=1,
        coalesce=True,
        replace_existing=True,
    )
    return scheduler
