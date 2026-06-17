"""The reconciler orchestrator: run the sweep steps in order.

A thin coordinator. It runs each step-service in order and returns a compact
per-step summary. It owns no billing logic — every step-service it calls reuses
the existing engine / absorption.

No reconciler-wide lock: safety is the per-paying-family ``PayingMemberLock`` that
every payment op already holds (and that the orphan cleanup checks before
deleting). Two concurrent sweeps (e.g. from two app instances) are therefore safe
— at worst they repeat idempotent work; they cannot corrupt state.

Logging here is intentional: the scheduler is the top of this call stack (there
is no router above it), so this is the layer that records what the background run
did, like the bulk fan-out does.
"""

import logging

from src.reconciler.service.reconciler.reconciler_invoice_fetch_sweep import (
    InvoiceFetchSweep,
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
from src.reconciler.service.reconciler.reconciler_stale_task_sweep import (
    StaleTaskSweep,
)

logger = logging.getLogger(__name__)


class ReconcilerService:
    """Run the scheduled reconciler sweep steps in order."""

    def __init__(
        self,
        orphan_cleanup_sweep: OrphanCleanupSweep,
        payment_push_sweep: PaymentPushSweep,
        invoice_fetch_sweep: InvoiceFetchSweep,
        stale_task_sweep: StaleTaskSweep,
    ) -> None:
        self._orphan_cleanup_sweep = orphan_cleanup_sweep
        self._payment_push_sweep = payment_push_sweep
        self._invoice_fetch_sweep = invoice_fetch_sweep
        self._stale_task_sweep = stale_task_sweep

    async def run(self) -> ReconcilerRunResult:
        """Run every step-service in order and return each one's ``SweepResult``."""
        logger.info("Reconciler sweep starting")
        sweeps: list[SweepResult] = []
        # Run order: invoice-fetch (refresh dates/charges) -> stale-task
        # recovery (re-run crashed tracked tasks, advancing their state +
        # converging) -> orphan-cleanup -> payment-push (config drift). The
        # push's sync now self-heals a dead sub natively (cancels the family +
        # nulls the sub id), so there is no separate Stripe-status pass.
        sweeps.append(await self._invoice_fetch_sweep.run())
        sweeps.append(await self._stale_task_sweep.run())
        sweeps.append(await self._orphan_cleanup_sweep.run())
        sweeps.append(await self._payment_push_sweep.run())
        logger.info(
            "Reconciler sweep complete (%d step(s))",
            len(sweeps),
        )
        return ReconcilerRunResult(sweeps=sweeps)
