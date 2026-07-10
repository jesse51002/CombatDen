"""Fire-and-forget, per-member-coalesced runner for the member video-taste
profile refresh.

Schedules ``MemberVideoProfileService.refresh_if_due`` as a detached
``asyncio`` task after a signal that a member's taste may have shifted (a class
booking or a video-rec click). Best-effort: the refresh is gated to at most once
per cooldown inside ``refresh_if_due``, so firing it freely is cheap, and a
refresh lost to a restart simply rebuilds on the next trigger or recs request.

**Per-member COALESCED.** If a refresh for a member is already in flight, a second
trigger for that member is DROPPED but marks the member DIRTY; when the in-flight
refresh finishes, a dirty member gets exactly ONE more refresh (which folds any
newer signal). So two concurrent first-signals (a click + a class sign-up) spawn
at most one concurrent build per member — not two paid summary+embedding builds —
and no signal is lost to the drop.

A refresh failure NEVER surfaces to the caller (the booking / click already
succeeded), but a FAILED build IS logged at ERROR with the member id: a silent
failure leaves ``video_profile_embedding`` NULL forever and personalization never
turns on, so the failure must be visible. Mirrors ``VideoFeedRefineRunner`` — a
``ClassVar`` task set so ``drain()`` sees every task, plus the ``ClassVar``
in-flight / dirty sets for the coalescing guard.
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
    """Kicks off + tracks detached, per-member-coalesced profile refreshes."""

    # ClassVars so drain() AND the coalescing guard see every task / in-flight
    # member regardless of which DI instance fired the start().
    _background_runs: ClassVar[set[asyncio.Task]] = set()
    _in_flight_members: ClassVar[set[UUID]] = set()
    _dirty_members: ClassVar[set[UUID]] = set()

    def __init__(self, profile_service: MemberVideoProfileService) -> None:
        self._profiles = profile_service

    def start(self, member_id: UUID, gym_id: UUID) -> None:
        """Fire a detached refresh-if-due for one member (best-effort).

        Coalesced: if a refresh for this member is already in flight the fire is
        dropped, but the member is marked dirty so exactly one follow-up refresh
        runs when the in-flight one finishes (no lost signal, no duplicate paid
        build for concurrent first-signals).
        """
        if member_id in self._in_flight_members:
            self._dirty_members.add(member_id)
            return
        self._in_flight_members.add(member_id)
        run = asyncio.create_task(self._run(member_id, gym_id))
        self._background_runs.add(run)
        run.add_done_callback(self._done)

    async def _run(self, member_id: UUID, gym_id: UUID) -> None:
        """Run refresh-if-due, log any build failure with context, then honor the
        dirty flag (a signal that arrived mid-flight) with exactly one more run."""
        try:
            await self._profiles.refresh_if_due(member_id, gym_id)
        except Exception:
            # A failed build leaves video_profile_embedding NULL, so personalization
            # silently never turns on for this member — log loudly (with the member
            # id) rather than swallow. The refresh is best-effort: the failure never
            # surfaces to the click / booking caller that fired it.
            logger.error(
                "Member video profile build failed for member %s — embedding stays "
                "NULL until the next trigger; personalization is off for them",
                member_id,
                exc_info=True,
            )
        finally:
            self._in_flight_members.discard(member_id)
            if member_id in self._dirty_members:
                self._dirty_members.discard(member_id)
                self.start(member_id, gym_id)

    @staticmethod
    def _done(task: asyncio.Task) -> None:
        MemberVideoProfileRefreshRunner._background_runs.discard(task)
        if task.cancelled():
            return
        exc = task.exception()
        if exc is not None:
            # _run catches build failures itself; this only fires on an
            # unexpected error in the runner scaffolding (e.g. the re-start).
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
        cls._in_flight_members.clear()
        cls._dirty_members.clear()
