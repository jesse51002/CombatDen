"""VideoRecsService — one rotating-category RAG video recommendation.

Serves a member ONE recommendation at a time. The served genre category rotates:
``idx = (count of the member's member_video_recs rows) % len(rotation)`` picks the
starting category from ``settings.video_rec_category_rotation``, so each served rec
advances the rotation by one. Within a category the gym's served, enriched feed is
ranked (RAG cosine blended with gym relevance + popularity when the member has a
profile embedding; the composite minus similarity when they don't), unrecommended
videos hard-partitioned first, and the top pick is taken. A category that has NO
videos falls through to the next in the rotation (wrapping). The served pick is
appended to ``member_video_recs`` and its ``rec_id`` is returned so the client can
record a click. Returns ``None`` when no category anywhere yields a video.
"""

from __future__ import annotations

from uuid import UUID

from pydantic import ValidationError
from schema.video import VideoGenre
from sqlalchemy import text

from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql
from src.videos import SQL_DIR
from src.videos.schema.video_recs_schema import (
    MemberVideoRec,
    RecommendedVideoCard,
)
from src.videos.service.member_video_profile_service import (
    MemberVideoProfileService,
)


class VideoRecsService:
    """Serve one rotating-category recommendation for a member."""

    def __init__(
        self,
        *,
        db_pool: DirectDatabasePool,
        profile_service: MemberVideoProfileService,
        weight_similarity: float,
        weight_relevance: float,
        weight_views: float,
        rotation: list[VideoGenre],
        rec_count: int,
    ) -> None:
        self._db = db_pool
        self._profiles = profile_service
        self._w_sim = weight_similarity
        self._w_rel = weight_relevance
        self._w_views = weight_views
        self._rotation = rotation
        self._rec_count = rec_count

    async def get_rec(
        self, gym_id: UUID, member_id: UUID
    ) -> MemberVideoRec | None:
        """The member's next rotating-category recommendation, or None.

        Verifies the member belongs to ``gym_id`` (``MemberNotInGymError``
        propagates → 404) READ-ONLY — a missing profile is NOT built here (the
        profile is (re)built only by the click / class-booking refresh triggers).
        ``load_embedding`` returns None for an unbuilt profile, in which case the
        ranking degrades to the no-similarity composite. The served category
        rotates by the member's total served-rec count; a category with no videos
        falls through to the next. The chosen pick is recorded to
        ``member_video_recs`` and returned with its ``rec_id``. Returns ``None``
        when no category yields a video (the route maps that to 404).
        """
        await self._profiles.verify_member_in_gym(member_id, gym_id)
        embedding = await self._profiles.load_embedding(member_id)

        served_count = await self._served_count(member_id)
        rotation = self._rotation
        start = served_count % len(rotation)
        for offset in range(len(rotation)):
            category = rotation[(start + offset) % len(rotation)]
            rows = await self._load_category_candidates(
                gym_id, member_id, embedding, category
            )
            pick = self._first_valid(rows)
            if pick is None:
                continue
            row, card = pick
            genre = VideoGenre(row["tag"])
            rec_id = await self._record_pick(gym_id, member_id, row, genre)
            return MemberVideoRec(rec_id=rec_id, category=genre, video=card)
        return None

    # ── candidate retrieval (one query per category) ──────────────

    async def _load_category_candidates(
        self,
        gym_id: UUID,
        member_id: UUID,
        embedding: str | None,
        category: VideoGenre,
    ) -> list[dict]:
        """Run the ranked candidate query for one genre (with/without similarity)."""
        base = {
            "gym_id": str(gym_id),
            "member_id": str(member_id),
            "category": category.value,
            "w_rel": self._w_rel,
            "w_views": self._w_views,
            "count": self._rec_count,
        }
        if embedding is None:
            sql = load_sql(SQL_DIR / "video_recs_candidates_no_embedding.sql")
            params = base
        else:
            sql = load_sql(SQL_DIR / "video_recs_candidates.sql")
            params = {
                **base,
                "member_embedding": embedding,
                "w_sim": self._w_sim,
            }
        async with self._db.session() as session:
            rows = (
                (await session.execute(text(sql), params)).mappings().all()
            )
        return [dict(r) for r in rows]

    @staticmethod
    def _first_valid(
        rows: list[dict],
    ) -> tuple[dict, RecommendedVideoCard] | None:
        """The first row that validates as a card, paired with the card."""
        for row in rows:
            try:
                card = RecommendedVideoCard.model_validate(dict(row))
            except ValidationError:
                continue
            return row, card
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
        self, gym_id: UUID, member_id: UUID, row: dict, genre: VideoGenre
    ) -> UUID:
        """Append the served pick to the rec history and return its rec_id."""
        sql = load_sql(SQL_DIR / "video_recs_record_insert.sql")
        params = {
            "member_id": str(member_id),
            "gym_id": str(gym_id),
            "video_id": row["video_id"],
            "category": genre.value,
            "score": row["score"],
        }
        async with self._db.session() as session, session.begin():
            result = (
                (await session.execute(text(sql), params)).mappings().fetchone()
            )
        return UUID(str(result["rec_id"]))
