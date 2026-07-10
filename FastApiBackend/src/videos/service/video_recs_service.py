"""VideoRecsService — one rotating-category RAG video recommendation.

Serves a member ONE recommendation at a time. The served genre category rotates:
``idx = (count of the member's member_video_recs rows) % len(rotation)`` picks the
starting category from ``settings.video_rec_category_rotation``, so each served rec
advances the rotation by one. The member's embedding is resolved ONCE up front (via
``verify_and_load_embedding``, which also guards membership) and passed into each
category's ranking read, so a rec issues a SINGLE member/embedding fetch, not one
per rotation category. Within a category the pick is the TOP of the unified feed
read (``VideoFeedService.rank_page_for_member`` filtered to that genre, ``limit=1``)
— cosine order to the member's taste embedding (gym relevance when they have no
embedding yet), with a σ-scaled owner boost and a decayed already-served penalty
baked into that read. The rec is a thin wrapper over the feed; this service only
drives the rotation, records the pick, and returns it. A category that yields NO
video falls through to the next in the rotation (wrapping). **The rec advances on
a re-serve via the decayed served penalty inside the feed read — there is no
already-served anti-join.** The served pick is appended to ``member_video_recs``
and its ``rec_id`` is returned so the client can record a click. Returns ``None``
when no category anywhere yields a video.
"""

from __future__ import annotations

from uuid import UUID

from schema.video import VideoGenre
from sqlalchemy import text

from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql
from src.videos import SQL_DIR
from src.videos.schema.video_recs_schema import MemberVideoRec
from src.videos.service.member_video_profile_service import (
    MemberVideoProfileService,
)
from src.videos.service.video_feed_service import VideoFeedService


class VideoRecsService:
    """Serve one rotating-category recommendation for a member."""

    def __init__(
        self,
        *,
        db_pool: DirectDatabasePool,
        profile_service: MemberVideoProfileService,
        feed_service: VideoFeedService,
        rotation: list[VideoGenre],
    ) -> None:
        self._db = db_pool
        self._profiles = profile_service
        self._feed = feed_service
        self._rotation = rotation

    async def get_rec(
        self, gym_id: UUID, member_id: UUID
    ) -> MemberVideoRec | None:
        """The member's next rotating-category recommendation, or None.

        Verifies the member belongs to ``gym_id`` and loads their embedding in ONE
        read via ``verify_and_load_embedding`` (``MemberNotInGymError`` propagates →
        404; a member not in the path gym can never rank a different gym's feed).
        READ-ONLY — a missing profile is NOT built here (the profile is (re)built
        only by the click / class-booking refresh triggers); an unbuilt embedding
        (None) just makes the feed read rank by gym relevance. That single resolved
        embedding is reused across every rotation category, so a rec issues one
        member fetch, not one per category. The served category rotates by the
        member's total served-rec count; a category with no video falls through to
        the next (wrapping). Within a category the pick is the TOP of
        ``rank_page_for_member`` for that genre (``limit=1``) — its decayed served
        penalty is what advances the pick on a re-serve, so there is no
        already-served anti-join. The chosen pick is recorded to
        ``member_video_recs`` and returned with its ``rec_id``. Returns ``None``
        when no category yields a video (the route maps that to 404).
        """
        embedding = await self._profiles.verify_and_load_embedding(
            member_id, gym_id
        )

        served_count = await self._served_count(member_id)
        rotation = self._rotation
        start = served_count % len(rotation)
        for offset in range(len(rotation)):
            category = rotation[(start + offset) % len(rotation)]
            cards, _ = await self._feed.rank_page_for_member(
                gym_id,
                member_id=member_id,
                member_embedding=embedding,
                video_type=category,
                limit=1,
                offset=0,
            )
            if not cards:
                continue
            card = cards[0]
            rec_id = await self._record_pick(
                gym_id, member_id, card.video_id, category
            )
            return MemberVideoRec(
                rec_id=rec_id, category=category, video=card
            )
        return None

    # ── rotation index + record served ────────────────────────────

    async def _served_count(self, member_id: UUID) -> int:
        """How many recs this member has been served (rotation index driver)."""
        sql = load_sql(SQL_DIR / "video_recs_served_count.sql")
        async with self._db.session() as session:
            row = (
                (
                    await session.execute(
                        text(sql), {"member_id": str(member_id)}
                    )
                )
                .mappings()
                .fetchone()
            )
        return int(row["n"]) if row is not None else 0

    async def _record_pick(
        self, gym_id: UUID, member_id: UUID, video_id: str, genre: VideoGenre
    ) -> UUID:
        """Append the served pick to the rec history and return its rec_id."""
        sql = load_sql(SQL_DIR / "video_recs_record_insert.sql")
        params = {
            "member_id": str(member_id),
            "gym_id": str(gym_id),
            "video_id": video_id,
            "category": genre.value,
        }
        async with self._db.session() as session, session.begin():
            result = (
                (await session.execute(text(sql), params)).mappings().fetchone()
            )
        return UUID(str(result["rec_id"]))
