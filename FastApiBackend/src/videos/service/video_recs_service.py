"""VideoRecsService — one rotating-category RAG video recommendation.

Serves a member ONE recommendation at a time. The served genre category rotates:
``idx = (count of the member's member_video_recs rows) % len(rotation)`` picks the
starting category from ``settings.video_rec_category_rotation``, so each served rec
advances the rotation by one. Within a category the gym's served feed is ranked by
PURE cosine similarity between the video's ``video_rag`` summary embedding and the
member's video-taste embedding (gym relevance when the member has no embedding
yet) — no composite blend, no weights, no stored score. A category that has NO
candidate falls through to the next in the rotation (wrapping). The ranking + the
candidate query live in ``VideoFeedService.load_next_rec_video`` (the rec is a
thin wrapper over the feed); this service only drives the rotation, records the
pick, and returns it. The served pick is appended to ``member_video_recs`` and its
``rec_id`` is returned so the client can record a click. Returns ``None`` when no
category anywhere yields a video.
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

        Verifies the member belongs to ``gym_id`` (``MemberNotInGymError``
        propagates → 404) READ-ONLY — a missing profile is NOT built here (the
        profile is (re)built only by the click / class-booking refresh triggers).
        ``load_embedding`` returns None for an unbuilt profile, in which case the
        ranking degrades to gym relevance. The embedding is loaded ONCE and passed
        into every per-category feed call. The served category rotates by the
        member's total served-rec count; a category with no candidate falls through
        to the next. The chosen pick is recorded to ``member_video_recs`` and
        returned with its ``rec_id``. Returns ``None`` when no category yields a
        video (the route maps that to 404).
        """
        await self._profiles.verify_member_in_gym(member_id, gym_id)
        embedding = await self._profiles.load_embedding(member_id)

        served_count = await self._served_count(member_id)
        rotation = self._rotation
        start = served_count % len(rotation)
        for offset in range(len(rotation)):
            category = rotation[(start + offset) % len(rotation)]
            candidate = await self._feed.load_next_rec_video(
                gym_id, member_id, category, embedding
            )
            if candidate is None:
                continue
            rec_id = await self._record_pick(
                gym_id, member_id, candidate.video_id, category
            )
            return MemberVideoRec(
                rec_id=rec_id, category=category, video=candidate.video
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
