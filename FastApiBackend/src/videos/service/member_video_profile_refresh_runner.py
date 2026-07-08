"""Fire-and-forget runner for the member video-taste profile refresh.

Schedules ``MemberVideoProfileService.refresh_if_due`` as a detached
``asyncio`` task after a signal that a member's taste may have shifted (a class
booking or a video-rec click). Best-effort: the refresh is gated to at most once
per cooldown inside ``refresh_if_due``, so firing it freely is cheap, and a
refresh lost to a restart simply rebuilds on the next trigger or recs request. A
refresh failure NEVER surfaces to the caller (the booking / click already
succeeded). Mirrors ``MembershipsInvoiceFetchRunner`` — a strong-ref set so the
task isn't GC'd mid-flight, plus a done-callback crash logger.
"""

import asyncio
import logging
from typing import ClassVar
from uuid import UUID

from src.videos.service.member_video_profile_service import (
    MemberVideoProfileService,
)

logger = logging.getLogger(__name__)


class MemberVideoProfileRefreshRunner:
    """Kicks off + tracks detached per-member profile refreshes."""

    # ClassVar so drain() sees every task regardless of the DI instance.
    _background_runs: ClassVar[set[asyncio.Task]] = set()

    def __init__(self, profile_service: MemberVideoProfileService) -> None:
        self._profiles = profile_service

    def start(self, member_id: UUID, gym_id: UUID) -> None:
        """Fire a detached refresh-if-due for one member (best-effort)."""
        run = asyncio.create_task(
            self._profiles.refresh_if_due(member_id, gym_id)
        )
        self._background_runs.add(run)
        run.add_done_callback(self._done)

    @staticmethod
    def _done(task: asyncio.Task) -> None:
        MemberVideoProfileRefreshRunner._background_runs.discard(task)
        if task.cancelled():
            return
        exc = task.exception()
        if exc is not None:
            logger.error("Member video profile refresh crashed", exc_info=exc)

    @classmethod
    async def drain(cls) -> None:
        """Cancel + await all in-flight refreshes (called from app lifespan)."""
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
                    "Member video profile refresh errored during drain",
                    exc_info=True,
                )
        cls._background_runs.clear()
