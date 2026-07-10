"""VideoSpecAuthoring — deterministic commit: diff guard + query generation + save.

Composes :class:`VideoSpecService` and :class:`VideoQueryGenerator` to implement
the shared "accept a draft" path used by both the conversational agent and the
feed refiner.  The diff guard prevents redundant query generation and DB writes
when the criteria have not changed.
"""

from __future__ import annotations

from uuid import UUID

from schema.video import GymVideoSpecSource

from src.videos.schema.video_spec_schema import (
    VideoSpecDraft,
    VideoSpecView,
)
from src.videos.service.video_query_generator import VideoQueryGenerator
from src.videos.service.video_spec_service import VideoSpecService


class VideoSpecAuthoring:
    """Shared deterministic commit: diff → query-gen → save.

    The diff guard checks whether the proposed criteria differ from the gym's
    current latest spec.  When they are identical, :meth:`commit` returns
    ``None`` and nothing is generated or written (cost-saving guard).  When they
    differ, queries are generated via :class:`VideoQueryGenerator`, a new version
    is appended via :class:`VideoSpecService`, and the new :class:`VideoSpecView`
    is returned.
    """

    def __init__(
        self,
        *,
        spec_service: VideoSpecService,
        query_generator: VideoQueryGenerator,
        query_count: int,
    ) -> None:
        self._spec_service = spec_service
        self._query_generator = query_generator
        self._query_count = query_count

    async def commit(
        self,
        gym_id: UUID,
        criteria: VideoSpecDraft,
        *,
        source: GymVideoSpecSource,
    ) -> VideoSpecView | None:
        """Diff the criteria, generate queries if changed, save, and return the view.

        Returns ``None`` when the criteria are identical to the gym's current
        latest spec (nothing generated or written).

        When only the display summaries changed (``short_videos_desc`` /
        ``short_avoid_desc``) but the query-affecting fields are unchanged
        (disciplines, ``videos_desc``, ``avoid_desc``), the existing queries are
        reused — no LLM call is made. A new version is still appended so the
        updated display summaries are persisted.

        When query-affecting fields changed (or no spec exists yet), new queries
        are generated via :class:`VideoQueryGenerator` before saving.
        """
        current = await self._spec_service.load_latest(gym_id)
        if current is not None and not self._criteria_changed(current, criteria):
            return None

        if current is None or self._query_criteria_changed(current, criteria):
            queries = await self._query_generator.generate(
                disciplines=criteria.disciplines,
                videos_desc=criteria.videos_desc,
                avoid_desc=criteria.avoid_desc,
                count=self._query_count,
            )
        else:
            # Only display summaries changed — reuse the current spec's queries.
            queries = current.queries

        view = await self._spec_service.save_version(
            gym_id, criteria, queries, source=source
        )
        # No enqueue: the VideoService worker derives which gym to run from
        # run / spec / curation timestamps, so this newly-saved admin_update
        # version is picked up on the worker's next tick (subject to run caps).
        return view

    @staticmethod
    def _query_criteria_changed(current: VideoSpecView, new: VideoSpecDraft) -> bool:
        """True when a query-affecting field changed (disciplines ordered,
        ``videos_desc``, or ``avoid_desc``). Summary-only edits return False."""
        if current.disciplines != [d.value for d in new.disciplines]:
            return True
        if current.videos_desc != new.videos_desc:
            return True
        return current.avoid_desc != new.avoid_desc

    @staticmethod
    def _criteria_changed(current: VideoSpecView, new: VideoSpecDraft) -> bool:
        """True when ANY criteria field differs — including discipline ORDER and
        the display summaries (``short_videos_desc`` / ``short_avoid_desc``)."""
        if current.disciplines != [d.value for d in new.disciplines]:
            return True
        if current.videos_desc != new.videos_desc:
            return True
        if current.avoid_desc != new.avoid_desc:
            return True
        if current.short_videos_desc != new.short_videos_desc:
            return True
        return current.short_avoid_desc != new.short_avoid_desc
