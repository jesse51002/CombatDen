"""The reconciler orchestrator: run the sweep behind a global lock.

A thin coordinator. It takes the single global sweep lease (one
``resource_locks`` key) so two app instances never sweep at once, then runs each
step-service in order and returns a compact per-step summary. It owns no billing
logic — every step-service it calls reuses the existing engine / absorption.

Logging here is intentional: the scheduler is the top of this call stack (there
is no router above it), so this is the layer that records what the background run
did, like the bulk fan-out does.
"""

import logging

from src.core.config import (
    RECONCILER_SWEEP_LOCK_KEY,
    RECONCILER_SWEEP_LOCK_TTL_SECONDS,
)
from src.reconciler.service.reconciler.reconciler_orphan_cleanup_sweep import (
    OrphanCleanupSweep,
)
from src.reconciler.service.reconciler.reconciler_payment_push_sweep import (
    PaymentPushSweep,
)
from src.reconciler.service.reconciler.reconciler_result import (
    ReconcilerRunResult,
    SweepResult,
)
from src.reconciler.service.reconciler.reconciler_subscription_status_sweep import (
    SubscriptionStatusSweep,
)
from src.shared.resource_lock import ResourceLock

logger = logging.getLogger(__name__)


class ReconcilerService:
    """Run the scheduled reconciler sweep behind the global sweep lock."""

    def __init__(
        self,
        resource_lock: ResourceLock,
        orphan_cleanup_sweep: OrphanCleanupSweep,
        payment_push_sweep: PaymentPushSweep,
        subscription_status_sweep: SubscriptionStatusSweep,
    ) -> None:
        self._resource_lock = resource_lock
        self._orphan_cleanup_sweep = orphan_cleanup_sweep
        self._payment_push_sweep = payment_push_sweep
        self._subscription_status_sweep = subscription_status_sweep

    async def run(self) -> ReconcilerRunResult:
        """Run one full sweep, unless another instance already holds the lock.

        Returns ``ran=False`` immediately when the global sweep lease is held
        elsewhere. Otherwise runs every step-service in order and returns each
        one's ``SweepResult``; the lease is always released on exit.
        """
        async with self._resource_lock.try_lock(
            RECONCILER_SWEEP_LOCK_KEY,
            ttl_seconds=RECONCILER_SWEEP_LOCK_TTL_SECONDS,
        ) as acquired:
            if not acquired:
                logger.info(
                    "Reconciler sweep lock held elsewhere; skipping this run",
                )
                return ReconcilerRunResult(ran=False)

            logger.info("Reconciler sweep starting")
            sweeps: list[SweepResult] = []
            # Final order is D -> B -> A -> C; steps are appended as added.
            sweeps.append(await self._subscription_status_sweep.run())
            sweeps.append(await self._orphan_cleanup_sweep.run())
            sweeps.append(await self._payment_push_sweep.run())
            logger.info(
                "Reconciler sweep complete (%d step(s))",
                len(sweeps),
            )
            return ReconcilerRunResult(ran=True, sweeps=sweeps)
