"""VideosService — pure delegating facade for the videos domain.

Composes: ``VideoFeedService`` (the unified live gym feed + pool reads + the
ungated owner management listing; the feed read backs the member rec too),
``VideoSpecService`` (spec DB read/write), ``VideoSpecAuthoring`` (deterministic
commit gate), ``VideoFeedRefiner`` (feed-learning refiner), ``VideoRecsService``
(the member's single rotating-category RAG recommendation), and
``VideoRecClickService`` (record a rec click → stamp + log + fire a profile
refresh).

The router injects this facade for every non-agent video operation; the
conversational agent uses it for the deterministic accept-path
(``save_accepted_spec``) and first-turn state seeding (``load_latest_spec``).

Template catalog reads have moved to ``PresetsTemplateService`` in the presets
domain. Showcase reads have moved to ``ThemeShowcaseService`` in the theme domain.
"""

from __future__ import annotations

from uuid import UUID

from schema.video import GymVideoSpecSource, VideoGenre

from src.videos.schema.video_recs_schema import (
    MemberVideoRec,
    VideoRecClickResponse,
)
from src.videos.schema.video_spec_schema import (
    VideoSpecDraft,
    VideoSpecView,
)
from src.videos.schema.videos_big_group import BigGroup
from src.videos.schema.videos_schema import (
    GymFeedSection,
    GymVideoCard,
    GymVideoSpecView,
)
from src.videos.service.video_feed_refiner import VideoFeedRefiner
from src.videos.service.video_feed_service import VideoFeedService
from src.videos.service.video_rec_click_service import VideoRecClickService
from src.videos.service.video_recs_service import VideoRecsService
from src.videos.service.video_spec_authoring import VideoSpecAuthoring
from src.videos.service.video_spec_service import VideoSpecService


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
        recs_service: VideoRecsService,
        click_service: VideoRecClickService,
    ) -> None:
        self._feed = feed_service
        self._spec_service = spec_service
        self._authoring = authoring
        self._feed_refiner = feed_refiner
        self._recs = recs_service
        self._click = click_service

    # ── live gym feed ─────────────────────────────────────────────

    async def load_feed_preview(
        self, gym_id: UUID, *, per_tag: int, rejected: bool = False
    ) -> list[GymFeedSection]:
        """The "All" preview — up to ``per_tag`` videos per genre in one windowed
        query. Delegates to VideoFeedService (the router just returns the sections
        wrapped in ``GymFeedPreview``)."""
        return await self._feed.load_feed_preview(
            gym_id, per_tag=per_tag, rejected=rejected
        )

    async def load_pool_videos(
        self, video_ids: list[str]
    ) -> list[GymVideoCard]:
        """Hydrate the named pooled videos by id (used by the presets template
        preview, which supplies its own id list)."""
        return await self._feed.load_pool_videos(video_ids)

    async def load_feed_page(
        self,
        gym_id: UUID,
        *,
        rejected: bool = False,
        video_type: VideoGenre | None = None,
        big_group: BigGroup | None = None,
        member_id: UUID | None = None,
        limit: int,
        offset: int,
    ) -> tuple[list[GymVideoCard], int]:
        """The unified real-gym feed page — delegates to VideoFeedService.

        ALWAYS merges the owner section with the latest completed run and serves
        only enriched+accepted videos. ``member_id`` optionally personalizes the
        ranking to that member's video-taste embedding (read-only; gym relevance
        when they have no profile) and decays their watch penalty.
        """
        return await self._feed.load_feed_page(
            gym_id,
            rejected=rejected,
            video_type=video_type,
            big_group=big_group,
            member_id=member_id,
            limit=limit,
            offset=offset,
        )

    async def load_owner_videos(
        self, gym_id: UUID, *, limit: int, offset: int
    ) -> tuple[list[GymVideoCard], int]:
        """The gym owner's UNGATED "Your videos" management listing — delegates
        to VideoFeedService. Not enriched-gated (an owner add shows instantly);
        each card carries ``enriched`` so the CRM can badge "processing…"."""
        return await self._feed.load_owner_videos(
            gym_id, limit=limit, offset=offset
        )

    # ── live gym spec (legacy projection) ────────────────────────

    async def load_gym_spec(self, gym_id: UUID) -> GymVideoSpecView | None:
        """A real gym's live spec as the legacy ``GymVideoSpecView`` — pure
        delegation. The projection (``disciplines`` → ``gym_type`` etc.) lives in
        ``VideoSpecService.load_latest_gym_view``. ``None`` when none authored."""
        return await self._spec_service.load_latest_gym_view(gym_id)

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

    # ── member rec + rec click (RAG read surface) ─────────────────

    async def get_video_rec(
        self, gym_id: UUID, member_id: UUID
    ) -> MemberVideoRec | None:
        """The member's next rotating-category recommendation (RAG-ranked).

        Records the served pick and returns it with its ``rec_id``; ``None`` when
        no category yields a video (the route maps that to 404).
        """
        return await self._recs.get_rec(gym_id, member_id)

    async def record_rec_click(
        self, gym_id: UUID, member_id: UUID, rec_id: UUID
    ) -> VideoRecClickResponse:
        """Record a member opening (clicking) a served recommendation."""
        return await self._click.record_click(gym_id, member_id, rec_id)
