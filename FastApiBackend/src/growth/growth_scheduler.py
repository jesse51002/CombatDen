"""APScheduler wiring for the growth-metric compute.

Infrastructure glue (a function module, not a service): builds an
``AsyncIOScheduler`` with a single interval job that recomputes every gym's
growth metrics. The app lifespan owns the scheduler's start/stop.

``next_run_time=now`` is what makes "compute at launch AND hourly" fall out of
ONE mechanism — there is deliberately no separate startup call. ``max_instances
=1`` + ``coalesce`` guard against in-process pile-up; the compute service's own
``ResourceLock`` guards across separate app instances.
"""

import logging
from datetime import UTC, datetime

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.interval import IntervalTrigger

from src.core.config import settings
from src.core.dependencies import DependencyInjector

logger = logging.getLogger(__name__)

GROWTH_JOB_ID = "growth_compute"


def build_growth_scheduler(container: DependencyInjector) -> AsyncIOScheduler:
    """Build the growth-compute scheduler (not started).

    Args:
        container: The DI container the job resolves ``GrowthComputeService``
            from.

    Returns:
        A configured ``AsyncIOScheduler`` the caller starts and shuts down.
    """
    scheduler = AsyncIOScheduler(timezone="UTC")

    async def _run_growth_compute() -> None:
        try:
            await container.growth_compute_service().compute_all_gyms()
        except Exception:
            logger.error("Growth compute run failed", exc_info=True)

    scheduler.add_job(
        _run_growth_compute,
        trigger=IntervalTrigger(
            minutes=settings.growth_compute_interval_minutes
        ),
        id=GROWTH_JOB_ID,
        max_instances=1,
        coalesce=True,
        replace_existing=True,
        next_run_time=datetime.now(UTC),
    )
    return scheduler
