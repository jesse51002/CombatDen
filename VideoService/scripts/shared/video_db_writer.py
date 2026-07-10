"""SQL writer for the VideoService pipeline scripts.

The read API never writes — every mutation (sync-gyms, the one-time import, and
later scrape/scan) goes through this writer. Each query lives in
``scripts/sql/*.sql`` (the "no inline SQL" rule); multi-statement mutations run in
one transaction. Multi-value fields (disciplines, source_queries, gym_type) are
written as JSON strings cast to ``jsonb`` in the SQL.
"""

from __future__ import annotations

import json
from collections.abc import Sequence
from pathlib import Path

from sqlalchemy import text

from schema import CostEntry, CostSource, Gym, VideoOutput
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql
from src.shared.util.video_id import video_id_from_url

from scripts.shared.video_rag_sidecar import VideoRagRecord, VideoRagSidecar

SQL_DIR = Path(__file__).resolve().parent.parent / "sql"


def _sql(name: str) -> str:
    return load_sql(SQL_DIR / name)


class VideoDbWriter:
    """Transactional writes into the ``video_*`` tables."""

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db = db_pool

    async def upsert_gym(self, gym: Gym) -> None:
        """Upsert one gym + its queries / classes / rewards (child rows are
        replaced wholesale). Does NOT touch the gym's feed (scan/import owns it)."""
        spec = gym.videos.specification
        async with self._db.session() as session:
            await session.execute(
                text(_sql("upsert_gym.sql")),
                {
                    "gym_id": gym.gym_id,
                    "gym_type": json.dumps([g.value for g in gym.gym_type]),
                    "theme": gym.theme,
                    "short_videos_desc": spec.short_videos_desc,
                    "short_avoid_desc": spec.short_avoid_desc,
                    "videos_desc": spec.videos_desc,
                    "avoid_desc": spec.avoid_desc,
                    "has_classes": gym.classes is not None,
                    "has_rewards": gym.rewards is not None,
                },
            )
            await session.execute(
                text(_sql("delete_gym_queries.sql")), {"gym_id": gym.gym_id}
            )
            if gym.videos.queries:
                await session.execute(
                    text(_sql("insert_gym_query.sql")),
                    [{"gym_id": gym.gym_id, "query": q} for q in gym.videos.queries],
                )
            await session.execute(
                text(_sql("delete_gym_classes.sql")), {"gym_id": gym.gym_id}
            )
            if gym.classes:
                await session.execute(
                    text(_sql("insert_gym_class.sql")),
                    [
                        {
                            "gym_id": gym.gym_id,
                            "name": c.name,
                            "image_url": c.image_url,
                            "description": c.description,
                            "instructor_name": c.instructor_name,
                            "instructor_bio": c.instructor_bio,
                            "instructor_image_url": c.instructor_image_url,
                        }
                        for c in gym.classes
                    ],
                )
            await session.execute(
                text(_sql("delete_gym_rewards.sql")), {"gym_id": gym.gym_id}
            )
            if gym.rewards:
                await session.execute(
                    text(_sql("insert_gym_reward.sql")),
                    [
                        {
                            "gym_id": gym.gym_id,
                            "title": r.title,
                            "image_url": r.image_url,
                            "price_label": r.price_label,
                            "points_cost": r.points_cost,
                        }
                        for r in gym.rewards
                    ],
                )
            await session.commit()

    async def upsert_videos(self, videos: Sequence[VideoOutput]) -> int:
        """Merge-upsert pooled videos by id. Returns the number written (videos
        whose url has no extractable id are skipped)."""
        rows = []
        for v in videos:
            vid = video_id_from_url(v.url)
            if not vid:
                continue
            rows.append(
                {
                    "video_id": vid,
                    "url": v.url,
                    "title": v.title,
                    "description": v.description,
                    "thumbnail_url": v.thumbnail_url,
                    "channel_name": v.channel_name,
                    "channel_url": v.channel_url,
                    "channel_avatar_url": v.channel_avatar_url,
                    "view_count": v.view_count,
                    "like_count": v.like_count,
                    "duration_seconds": v.duration_seconds,
                    "tag": v.tag.value if v.tag else None,
                    "disciplines": json.dumps([g.value for g in v.gym_type]),
                    "source_queries": json.dumps(list(v.source_queries)),
                    "relevance_index": v.relevance_index,
                    "transcript_error": v.transcript_error,
                    "transcript": v.transcript,
                }
            )
        if not rows:
            return 0
        async with self._db.session() as session:
            await session.execute(text(_sql("upsert_video.sql")), rows)
            await session.commit()
        return len(rows)

    async def upsert_video_rag(self, records: Sequence[VideoRagRecord]) -> int:
        """Upsert enriched RAG rows from the template sidecar (FK-safe insert,
        ON CONFLICT DO NOTHING — SEEDS video_rag, never clobbers a live worker
        enrichment). Facets are JSON-encoded and the embedding floats are rendered
        to the pgvector text literal here. Returns the number of rows attempted."""
        rows = [
            {
                "video_id": r.video_id,
                "summary": r.summary,
                "facets": json.dumps(r.facets),
                "embedding": VideoRagSidecar.to_pgvector(r.embedding),
                "embedding_model": r.embedding_model,
            }
            for r in records
        ]
        if not rows:
            return 0
        async with self._db.session() as session:
            await session.execute(text(_sql("insert_video_rag.sql")), rows)
            await session.commit()
        return len(rows)

    async def set_gym_feed(
        self, gym_id: str, good_ids: Sequence[str], rejected_ids: Sequence[str]
    ) -> None:
        """Overwrite a gym's curated feed: clear its rows, then insert good +
        rejected (ids not present in the pool are silently skipped)."""
        insert = text(_sql("insert_gym_feed.sql"))
        async with self._db.session() as session:
            await session.execute(text(_sql("delete_gym_feed.sql")), {"gym_id": gym_id})
            if good_ids:
                await session.execute(
                    insert,
                    {"gym_id": gym_id, "video_ids": list(good_ids), "status": "good"},
                )
            if rejected_ids:
                await session.execute(
                    insert,
                    {
                        "gym_id": gym_id,
                        "video_ids": list(rejected_ids),
                        "status": "rejected",
                    },
                )
            await session.commit()

    async def append_cost(self, entry: CostEntry, gym_id: str | None = None) -> None:
        """Append one legacy spend-ledger row into ``cost_log``. ``gym_id``
        attributes per-gym scan spend; no run is associated (the old global
        ledger didn't record which run a scan belonged to)."""
        async with self._db.session() as session:
            await session.execute(
                text(_sql("insert_cost.sql")),
                {
                    "source": CostSource.video.value,
                    "run_id": None,
                    "gym_id": gym_id,
                    "stage": entry.execution_type.value,
                    "model": None,
                    "cost_usd": entry.total_usd,
                    "breakdown": json.dumps(entry.breakdown),
                    "note": entry.note,
                    "created_at": entry.at,
                },
            )
            await session.commit()
