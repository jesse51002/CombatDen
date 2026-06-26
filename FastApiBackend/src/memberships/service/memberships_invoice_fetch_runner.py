"""Fire-and-forget runner for the on-demand post-op invoice fetch.

Schedules ``MemberMembershipsInvoiceFetch.fetch_for_payer`` as a detached
``asyncio`` task right after an invoice-creating membership op returns (AFTER the
payer lock releases, so the fetch never extends lock-hold). Best-effort: the
webhook + twice-daily cron sweep are backstops, so a fetch lost to a restart is
still covered. Mirrors ``TasksExecutor.start_in_background`` — a strong-ref set so
the task isn't GC'd mid-flight, plus a done-callback crash logger.
"""

import asyncio
import logging
from typing import ClassVar
from uuid import UUID

from src.core.config import settings
from src.memberships.service.memberships_invoice_fetch import (
    MemberMembershipsInvoiceFetch,
)

logger = logging.getLogger(__name__)


class MembershipsInvoiceFetchRunner:
    """Kicks off + tracks detached per-payer invoice fetches."""

    # ClassVar so drain() sees every task regardless of the DI instance.
    _background_runs: ClassVar[set[asyncio.Task]] = set()

    def __init__(self, invoice_fetch: MemberMembershipsInvoiceFetch) -> None:
        self._invoice_fetch = invoice_fetch

    def start_for_payer(self, payer_member_id: UUID, op_start: int) -> None:
        """Fire a detached fetch for one payer (no-op when disabled)."""
        if not settings.invoice_fetch_on_demand_enabled:
            return
        run = asyncio.create_task(
            self._invoice_fetch.fetch_for_payer(payer_member_id, op_start)
        )
        self._background_runs.add(run)
        run.add_done_callback(self._done)

    @staticmethod
    def _done(task: asyncio.Task) -> None:
        MembershipsInvoiceFetchRunner._background_runs.discard(task)
        if task.cancelled():
            return
        exc = task.exception()
        if exc is not None:
            logger.error("On-demand invoice fetch crashed", exc_info=exc)

    @classmethod
    async def drain(cls) -> None:
        """Cancel + await all in-flight fetches (called from app lifespan)."""
        runs = list(cls._background_runs)
        for run in runs:
            run.cancel()
        for run in runs:
            try:
                await run
            except asyncio.CancelledError:
                pass
            except Exception:
                logger.error(
                    "On-demand invoice fetch errored during drain",
                    exc_info=True,
                )
        cls._background_runs.clear()
