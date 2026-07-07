"""VideosService — pure delegating facade for the videos domain.

Composes: ``VideoFeedService`` (live gym feed + pool reads), ``VideoSpecService``
(spec DB read/write), ``VideoSpecAuthoring`` (deterministic commit gate),
``VideoFeedRefiner`` (feed-learning refiner), ``VideosWorkerStatusService``
(read-only worker state), ``VideoRecsService`` (member RAG recommendations), and
``VideoSearchService`` (semantic feed search).

The router injects this facade for every non-agent video operation; the
conversational agent uses it for the deterministic accept-path
(``save_accepted_spec``) and first-turn state seeding (``load_latest_spec``).

Template catalog reads have moved to ``PresetsTemplateService`` in the presets
domain. Showcase reads have moved to ``ThemeShowcaseService`` in the theme domain.
"""

from __future__ import annotations

from uuid import UUID

from schema.video import GymVideoSpecSource, VideoGenre

from src.videos.schema.video_recs_schema import MemberVideoRecsResponse
from src.videos.schema.video_search_schema import SearchResultCard
from src.videos.schema.video_spec_schema import (
    VideoSpecDraft,
    VideoSpecView,
)
from src.videos.schema.video_worker_schema import VideoWorkerStatusResponse
from src.videos.schema.videos_big_group import BigGroup
from src.videos.schema.videos_schema import (
    GymVideoCard,
    GymVideoSpecView,
)
from src.videos.service.video_feed_refiner import VideoFeedRefiner
from src.videos.service.video_feed_service import VideoFeedService
from src.videos.service.video_recs_service import VideoRecsService
from src.videos.service.video_search_service import VideoSearchService
from src.videos.service.video_spec_authoring import VideoSpecAuthoring
from src.videos.service.video_spec_service import VideoSpecService
from src.videos.service.videos_worker_status_service import (
    VideosWorkerStatusService,
)


class VideosService:
    """Pure facade: delegates every operation to the appropriate concern service.

    The router and the video agent both reference this class by name; the public
    API is intentionally stable and minimal.
    """

    def __init__(
        self,
        feed_service: VideoFeedService,
        spec_service: VideoSpecService,
        authoring: VideoSpecAuthoring,
        feed_refiner: VideoFeedRefiner,
        worker_status: VideosWorkerStatusService,
        recs_service: VideoRecsService,
        search_service: VideoSearchService,
    ) -> None:
        self._feed = feed_service
        self._spec_service = spec_service
        self._authoring = authoring
        self._feed_refiner = feed_refiner
        self._worker_status = worker_status
        self._recs = recs_service
        self._search = search_service

    # ── live gym feed ─────────────────────────────────────────────

    async def load_feed_ids(
        self, gym_id: UUID, *, owner: bool = False, rejected: bool = False
    ) -> list[str]:
        return await self._feed.load_feed_ids(
            gym_id, owner=owner, rejected=rejected
        )

    async def load_pool_videos(
        self, video_ids: list[str]
    ) -> list[GymVideoCard]:
        return await self._feed.load_pool_videos(video_ids)

    async def load_feed_page(
        self,
        gym_id: UUID,
        *,
        owner: bool = False,
        rejected: bool = False,
        video_type: VideoGenre | None = None,
        big_group: BigGroup | None = None,
        limit: int,
        offset: int,
    ) -> tuple[list[GymVideoCard], int]:
        """Paginated real-gym feed page — delegates to VideoFeedService."""
        return await self._feed.load_feed_page(
            gym_id,
            owner=owner,
            rejected=rejected,
            video_type=video_type,
            big_group=big_group,
            limit=limit,
            offset=offset,
        )

    # ── live gym spec (legacy projection) ────────────────────────

    async def load_gym_spec(self, gym_id: UUID) -> GymVideoSpecView | None:
        """A real gym's live spec as a ``GymVideoSpecView``.

        Delegates to ``VideoSpecService.load_latest`` and converts the result
        to the legacy ``GymVideoSpecView`` shape (``gym_type`` field name,
        no ``queries`` / ``source`` / ``created_at``). Returns ``None`` when
        no spec has been authored yet.
        """
        spec = await self._spec_service.load_latest(gym_id)
        if spec is None:
            return None
        return GymVideoSpecView(
            gym_id=spec.gym_id,
            gym_type=spec.disciplines,
            short_videos_desc=spec.short_videos_desc,
            short_avoid_desc=spec.short_avoid_desc,
            videos_desc=spec.videos_desc,
            avoid_desc=spec.avoid_desc,
            imported_from=spec.imported_from,
        )

    # ── owner feed edits ──────────────────────────────────────────

    async def lookup_feed_video(self, url: str) -> GymVideoCard:
        return await self._feed.lookup_feed_video(url)

    async def add_feed_video(self, gym_id: UUID, url: str) -> GymVideoCard:
        return await self._feed.add_feed_video(gym_id, url)

    async def remove_feed_video(
        self,
        gym_id: UUID,
        video_id: str,
        *,
        owner: bool = False,
        reason: str | None = None,
    ) -> None:
        return await self._feed.remove_feed_video(
            gym_id, video_id, owner=owner, reason=reason
        )

    async def keep_feed_video(
        self,
        gym_id: UUID,
        video_id: str,
        *,
        accept_reason: str | None = None,
    ) -> None:
        return await self._feed.keep_feed_video(
            gym_id, video_id, accept_reason=accept_reason
        )

    # ── spec authoring + refine ───────────────────────────────────

    async def load_latest_spec(self, gym_id: UUID) -> VideoSpecView | None:
        """The gym's latest spec version, or None when none exists yet."""
        return await self._spec_service.load_latest(gym_id)

    async def save_accepted_spec(
        self, gym_id: UUID, criteria: VideoSpecDraft
    ) -> VideoSpecView | None:
        """Commit an accepted criteria draft: diff guard → query gen → save.

        Returns the new :class:`VideoSpecView` when the criteria differed from
        the current spec and a new version was written; ``None`` when the criteria
        were unchanged (nothing was written).
        """
        return await self._authoring.commit(
            gym_id, criteria, source=GymVideoSpecSource.admin_update
        )

    async def refine_from_feed(self, gym_id: UUID) -> VideoSpecView | None:
        return await self._feed_refiner.refine_from_feed(gym_id)

    # ── worker status (read-only) ─────────────────────────────────

    async def load_worker_status(
        self, gym_id: UUID
    ) -> VideoWorkerStatusResponse:
        """The gym's video-worker state (last refresh, running, last run)."""
        return await self._worker_status.status(gym_id)

    # ── member recs + semantic search (RAG read surface) ──────────

    async def get_video_recs(
        self,
        gym_id: UUID,
        member_id: UUID,
        *,
        per_bucket: int,
        record: bool,
    ) -> MemberVideoRecsResponse:
        """A member's mood-bucketed video recommendations (RAG-ranked)."""
        return await self._recs.get_recs(
            gym_id, member_id, per_bucket=per_bucket, record=record
        )

    async def search_videos(
        self, gym_id: UUID, q: str, limit: int
    ) -> list[SearchResultCard]:
        """Semantic search over the gym's served feed (most-similar first)."""
        return await self._search.search(gym_id, q, limit)
