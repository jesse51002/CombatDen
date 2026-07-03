"""VideoRecsService — mood-bucketed RAG video recommendations for a member.

Ensures the member's 5 bucket profiles exist (:class:`MemberVideoProfileService`),
then runs one candidate query per bucket (five sequential reads — fine at this
scale): retrieve the gym's served, enriched feed, filter to the bucket's genres,
rank by a blended score (RAG cosine + gym relevance + popularity) with
unrecommended videos hard-partitioned first. On ``record=True`` the served rows
are written to ``member_video_recs`` (freshness history); ``record=False`` (CRM
preview) writes nothing.
"""

from __future__ import annotations

from uuid import UUID

from schema.video import MoodBucket
from sqlalchemy import text

from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql
from src.videos import SQL_DIR
from src.videos.schema.video_mood_bucket import genres_for_bucket
from src.videos.schema.video_recs_schema import (
    MemberVideoRecsResponse,
    RecBucket,
    RecommendedVideoCard,
)
from src.videos.service.member_video_profile_service import (
    MemberVideoProfileService,
)


class VideoRecsService:
    """Retrieve + rank per-bucket video recommendations for a member."""

    def __init__(
        self,
        *,
        db_pool: DirectDatabasePool,
        profile_service: MemberVideoProfileService,
        weight_similarity: float,
        weight_relevance: float,
        weight_views: float,
    ) -> None:
        self._db = db_pool
        self._profiles = profile_service
        self._w_sim = weight_similarity
        self._w_rel = weight_relevance
        self._w_views = weight_views

    async def get_recs(
        self,
        gym_id: UUID,
        member_id: UUID,
        *,
        per_bucket: int,
        record: bool,
    ) -> MemberVideoRecsResponse:
        """Top-``per_bucket`` recommendations per mood bucket for the member.

        Builds/refreshes the member's profiles, retrieves + ranks each bucket,
        and (when ``record``) records the served rows.
        """
        await self._profiles.ensure_profiles(member_id, gym_id)
        embeddings = await self._profiles.load_embeddings(member_id)

        out: list[RecBucket] = []
        served: list[dict] = []
        for bucket in MoodBucket:
            cards = await self._recs_for_bucket(
                gym_id, member_id, bucket, embeddings.get(bucket), per_bucket,
                served if record else None,
            )
            out.append(RecBucket(bucket=bucket, videos=cards))

        if record and served:
            await self._record_served(gym_id, member_id, served)
        return MemberVideoRecsResponse(buckets=out)

    # ── per-bucket retrieval ──────────────────────────────────────

    async def _recs_for_bucket(
        self,
        gym_id: UUID,
        member_id: UUID,
        bucket: MoodBucket,
        embedding: str | None,
        per_bucket: int,
        served: list[dict] | None,
    ) -> list[RecommendedVideoCard]:
        """Retrieve + rank one bucket; append served rows when recording."""
        if embedding is None:
            return []
        rows = await self._load_candidates(
            gym_id, member_id, bucket, embedding, per_bucket
        )
        cards: list[RecommendedVideoCard] = []
        for row in rows:
            try:
                card = RecommendedVideoCard.model_validate(dict(row))
            except ValueError:
                continue
            cards.append(card)
            if served is not None:
                served.append(
                    {
                        "video_id": row["video_id"],
                        "bucket": bucket.value,
                        "score": row["score"],
                    }
                )
        return cards

    async def _load_candidates(
        self,
        gym_id: UUID,
        member_id: UUID,
        bucket: MoodBucket,
        embedding: str,
        per_bucket: int,
    ) -> list[dict]:
        """Run the candidate query for one bucket."""
        sql = load_sql(SQL_DIR / "video_recs_candidates.sql")
        params = {
            "gym_id": str(gym_id),
            "member_id": str(member_id),
            "profile_embedding": embedding,
            "genres": [g.value for g in genres_for_bucket(bucket)],
            "w_sim": self._w_sim,
            "w_rel": self._w_rel,
            "w_views": self._w_views,
            "per_bucket": per_bucket,
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
        """Upsert every served row into the member's rec history."""
        sql = load_sql(SQL_DIR / "video_recs_record_upsert.sql")
        params = [
            {
                "member_id": str(member_id),
                "gym_id": str(gym_id),
                "video_id": row["video_id"],
                "bucket": row["bucket"],
                "score": row["score"],
            }
            for row in served
        ]
        async with self._db.session() as session, session.begin():
            await session.execute(text(sql), params)
