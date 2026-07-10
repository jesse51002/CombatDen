"""Fire-and-forget, per-gym-coalesced runner for the feed-learning spec refine.

Fired after a manual feed curation (a reject or a keep/un-reject) commits, it runs
``VideoFeedRefiner.refine_from_feed`` as a detached ``asyncio`` task so the curation
response never waits on the LLM refine. The refiner folds the gym's unconsumed
``curation_type='manual'`` signals into a new ``feed_update`` ``gym_video_spec``
version (via ``VideoSpecAuthoring.commit(source=feed_update)``); the VideoService
worker's scan sweep then re-judges the gym's auto feed rows against it ≥1h later
(that wait lives in the worker, not here).

**Per-gym COALESCED.** If a refine for a gym is already in flight, a second trigger
for that gym is DROPPED but marks the gym DIRTY; when the in-flight refine finishes,
a dirty gym gets exactly ONE more refine — which reloads and folds any signal that
arrived mid-flight. This closes a lost-signal hole: a curation that lands while a
refine is running is dropped by the in-flight guard, and once the refine commits a
``feed_update`` version the signals query (anchored on the latest spec's
``created_at``) can treat it as consumed — so without the dirty re-run its signal
could be lost permanently. So a burst of N rapid rejects spawns at most one
in-flight refine plus one coalesced follow-up per gym (two refines), never N, and
never zero-that-drops-the-last-signal.

Best-effort: ``refine_from_feed`` is a no-op when there are no new signals, and a
refine failure NEVER surfaces to the curation caller (the reject/keep already
succeeded). Mirrors ``MemberVideoProfileRefreshRunner`` — a ``ClassVar`` task set so
``drain()`` sees every task, plus a done-callback crash logger — with the added
``ClassVar`` in-flight + dirty gym sets for the coalescing guard.
"""

import asyncio
import logging
from typing import ClassVar
from uuid import UUID

from src.videos.service.video_feed_refiner import VideoFeedRefiner

logger = logging.getLogger(__name__)


class VideoFeedRefineRunner:
    """Kicks off + tracks detached, per-gym-coalesced feed-learning refines."""

    # ClassVars so drain() AND the coalescing guard see every task / in-flight /
    # dirty gym regardless of which DI instance fired the start().
    _background_runs: ClassVar[set[asyncio.Task]] = set()
    _in_flight_gyms: ClassVar[set[UUID]] = set()
    _dirty_gyms: ClassVar[set[UUID]] = set()

    def __init__(self, feed_refiner: VideoFeedRefiner) -> None:
        self._refiner = feed_refiner

    def start(self, gym_id: UUID) -> None:
        """Fire a detached refine for one gym (coalesced, best-effort).

        If a refine for this gym is already in flight the fire is dropped, but the
        gym is marked dirty so exactly one follow-up refine runs when the in-flight
        one finishes — reloading and folding any signal that arrived mid-flight, so
        the last curation of a burst is never lost.
        """
        if gym_id in self._in_flight_gyms:
            self._dirty_gyms.add(gym_id)
            return
        self._in_flight_gyms.add(gym_id)
        run = asyncio.create_task(self._run(gym_id))
        self._background_runs.add(run)
        run.add_done_callback(self._done)

    async def _run(self, gym_id: UUID) -> None:
        """Run the refine, then always clear the in-flight guard and honor the
        dirty flag with exactly one follow-up refine (so a signal that arrived
        mid-flight — and would otherwise be dropped then consumed by the anchor —
        is still folded). The re-run fires from ``finally`` so it happens even when
        the refine raised; the original exception still propagates to ``_done`` for
        the crash log."""
        try:
            await self._refiner.refine_from_feed(gym_id)
        finally:
            self._in_flight_gyms.discard(gym_id)
            if gym_id in self._dirty_gyms:
                self._dirty_gyms.discard(gym_id)
                self.start(gym_id)

    @staticmethod
    def _done(task: asyncio.Task) -> None:
        VideoFeedRefineRunner._background_runs.discard(task)
        if task.cancelled():
            return
        exc = task.exception()
        if exc is not None:
            logger.error("Video feed refine crashed", exc_info=exc)

    @classmethod
    async def drain(cls) -> None:
        """Cancel + await all in-flight refines (called from app lifespan)."""
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
                    "Video feed refine errored during drain", exc_info=True
                )
        cls._background_runs.clear()
        cls._in_flight_gyms.clear()
        cls._dirty_gyms.clear()
