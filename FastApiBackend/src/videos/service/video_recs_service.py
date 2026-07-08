"""VideoRecsService — genre-categorized RAG video recommendations for a member.

Ensures the member's video-taste profile exists
(:class:`MemberVideoProfileService`), then ranks the gym's served, enriched feed
ONCE against the member's single profile embedding (RAG cosine blended with gym
relevance + popularity, unrecommended videos hard-partitioned first). The ranked
candidates are then grouped by the video's genre (``video.tag``) directly — one
:class:`RecCategory` per genre that appears, in rank (first-appearance) order —
and each category is sliced to ``per_category``. A member with no embedding yet
falls back to the no-similarity degrade query so they still get recs. On
``record=True`` the served rows are written to ``member_video_recs`` (freshness
history), each stamped with its genre category; ``record=False`` (CRM preview)
writes nothing.
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
    MemberVideoRecsResponse,
    RecCategory,
    RecommendedVideoCard,
)
from src.videos.service.member_video_profile_service import (
    MemberNotInGymError,
    MemberVideoProfileService,
)


class VideoRecsService:
    """Rank a member's recommendations once, then group them by genre category."""

    def __init__(
        self,
        *,
        db_pool: DirectDatabasePool,
        profile_service: MemberVideoProfileService,
        weight_similarity: float,
        weight_relevance: float,
        weight_views: float,
        candidate_limit: int,
    ) -> None:
        self._db = db_pool
        self._profiles = profile_service
        self._w_sim = weight_similarity
        self._w_rel = weight_relevance
        self._w_views = weight_views
        self._candidate_limit = candidate_limit

    async def get_recs(
        self,
        gym_id: UUID,
        member_id: UUID,
        *,
        per_category: int,
        record: bool,
    ) -> MemberVideoRecsResponse:
        """Top-``per_category`` recommendations per genre category for the member.

        Verifies the member belongs to ``gym_id`` (``MemberNotInGymError``
        propagates → 404) and lazily builds a missing profile. A profile-BUILD
        failure (LLM / embedding provider down or misconfigured) is best-effort:
        it must NOT blank the member's feed, so the member falls through with no
        embedding to the no-similarity degrade ranking rather than 500ing (the
        approved "degrade, don't 500" spec). Such a failure still surfaces via
        the ``/videos/search`` path (which raises) and the refresh runner's crash
        log. The ranked rows are grouped by the video's genre (``video.tag``)
        directly — one category per genre that appears, in rank order — and each
        is sliced to ``per_category``; ``record`` appends the served rows.
        """
        try:
            await self._profiles.ensure_profile(member_id, gym_id)
        except MemberNotInGymError:
            # The member↔gym ownership guard is a hard 404 — never degraded.
            raise
        except Exception:
            # Best-effort personalization: a failed profile build must not blank
            # the member's feed. Fall through with no embedding to the
            # no-similarity degrade query below.
            pass
        embedding = await self._profiles.load_embedding(member_id)

        rows = await self._load_candidates(gym_id, member_id, embedding)

        # Group by the video's genre category directly, preserving rank
        # (first-appearance) order, and cap each category to per_category.
        categories: dict[VideoGenre, list[RecommendedVideoCard]] = {}
        served: list[dict] = []
        for row in rows:
            genre = VideoGenre(row["tag"])
            cat_videos = categories.setdefault(genre, [])
            if len(cat_videos) >= per_category:
                continue
            try:
                card = RecommendedVideoCard.model_validate(dict(row))
            except ValidationError:
                continue
            cat_videos.append(card)
            if record:
                served.append(
                    {
                        "video_id": row["video_id"],
                        "category": genre.value,
                        "score": row["score"],
                    }
                )

        if record and served:
            await self._record_served(gym_id, member_id, served)

        out = [
            RecCategory(category=genre, videos=videos)
            for genre, videos in categories.items()
            if videos
        ]
        return MemberVideoRecsResponse(categories=out)

    # ── candidate retrieval (one ranked query) ────────────────────

    async def _load_candidates(
        self, gym_id: UUID, member_id: UUID, embedding: str | None
    ) -> list[dict]:
        """Run the single ranked candidate query (with or without similarity)."""
        base = {
            "gym_id": str(gym_id),
            "member_id": str(member_id),
            "w_rel": self._w_rel,
            "w_views": self._w_views,
            "candidate_limit": self._candidate_limit,
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

    # ── record served (record=true only) ──────────────────────────

    async def _record_served(
        self, gym_id: UUID, member_id: UUID, served: list[dict]
    ) -> None:
        """Append every served row to the member's rec history (event log)."""
        sql = load_sql(SQL_DIR / "video_recs_record_insert.sql")
        params = [
            {
                "member_id": str(member_id),
                "gym_id": str(gym_id),
                "video_id": row["video_id"],
                "category": row["category"],
                "score": row["score"],
            }
            for row in served
        ]
        async with self._db.session() as session, session.begin():
            await session.execute(text(sql), params)
