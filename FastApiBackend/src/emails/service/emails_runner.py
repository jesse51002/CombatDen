"""Fire-and-forget runner for delivering one claimed email.

Schedules ``EmailsService.send_now`` as a detached ``asyncio`` task AFTER the
transaction that claimed the row has committed. Delivery must never sit
inside a request: the employee/member was created regardless, and a slow or
down mail provider must not slow (or fail) that write.

Best-effort by design. A send lost to a restart is not lost at all — the
``email_log`` row stays ``pending`` and the reconciler's retry sweep picks it
up. Mirrors ``MemberVideoProfileRefreshRunner``: a ``ClassVar`` task set so
``drain()`` sees every task regardless of which DI instance fired it. There
is deliberately NO coalescing — every ``email_id`` is a distinct message,
never a recomputation of the same thing.
"""

import asyncio
import logging
from typing import ClassVar
from uuid import UUID

from src.emails.service.emails_service import EmailsService

logger = logging.getLogger(__name__)


class EmailsRunner:
    """Kicks off + tracks detached email deliveries."""

    _background_runs: ClassVar[set[asyncio.Task]] = set()

    def __init__(self, emails_service: EmailsService) -> None:
        self._emails = emails_service

    def start(self, email_id: UUID) -> None:
        """Fire a detached delivery for one claimed email (best-effort)."""
        run = asyncio.create_task(self._emails.send_now(email_id))
        self._background_runs.add(run)
        run.add_done_callback(self._done)

    @staticmethod
    def _done(task: asyncio.Task) -> None:
        EmailsRunner._background_runs.discard(task)
        if task.cancelled():
            return
        exc = task.exception()
        if exc is not None:
            # send_now swallows every send failure itself, so this only
            # fires on an unexpected error in the runner scaffolding.
            logger.error("Email delivery crashed", exc_info=exc)

    @classmethod
    async def drain(cls) -> None:
        """Cancel + await all in-flight deliveries (app lifespan shutdown).

        A cancelled delivery leaves its row unfinished, which the retry
        sweep recovers — nothing is lost by draining hard at shutdown.
        """
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
                    "Email delivery errored during drain", exc_info=True
                )
        cls._background_runs.clear()
