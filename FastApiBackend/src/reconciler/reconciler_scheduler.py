"""APScheduler wiring for the scheduled reconciler.

Infrastructure glue (a function module, not a service): builds an
``AsyncIOScheduler`` with a single cron job that fires the reconciler twice a
day (UTC). The app lifespan owns the scheduler's start/stop. ``max_instances=1``
+ ``coalesce`` guard against in-process pile-up; the ``resource_locks`` global
key (inside ``ReconcilerService``) guards across separate app instances.
"""

import logging

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger

from src.core.config import settings
from src.core.dependencies import DependencyInjector

logger = logging.getLogger(__name__)

RECONCILER_JOB_ID = "reconciler_sweep"


def build_scheduler(container: DependencyInjector) -> AsyncIOScheduler:
    """Build the reconciler scheduler (not started).

    Args:
        container: The DI container the job resolves ``ReconcilerService`` from.

    Returns:
        A configured ``AsyncIOScheduler`` the caller starts and shuts down.
    """
    scheduler = AsyncIOScheduler(timezone="UTC")

    async def _run_reconciler() -> None:
        try:
            await container.reconciler_service().run()
        except Exception:
            logger.error("Reconciler sweep run failed", exc_info=True)

    hours = ",".join(str(hour) for hour in settings.reconciler_cron_hours)
    scheduler.add_job(
        _run_reconciler,
        trigger=CronTrigger(hour=hours, minute=0, timezone="UTC"),
        id=RECONCILER_JOB_ID,
        max_instances=1,
        coalesce=True,
        replace_existing=True,
    )
    return scheduler
