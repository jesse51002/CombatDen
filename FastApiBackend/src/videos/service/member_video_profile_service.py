"""MemberVideoProfileService — build + read a member's per-bucket RAG profiles.

One ``member_video_profile`` row per mood bucket holds the profile TEXT a
member's recommendations are retrieved against, plus its embedding. v1 profile
text is a DETERMINISTIC template built from member facts (rank, trailing-window
attendance, top classes, gym disciplines) — the interface is the point; the text
gets smarter later. Built lazily on first recs request and rebuilt when stale.

The five bucket texts are embedded in ONE ``embed`` batch call and upserted
together. Embeddings are stored/read as pgvector text form and every produced
vector is length-checked against the pinned embedding dimension (a cross-service
contract with the VideoService worker that writes ``video_rag.embedding``).
"""

from __future__ import annotations

import json
from datetime import UTC, datetime, timedelta
from uuid import UUID

from schema.video import MoodBucket
from sqlalchemy import text

from src.shared.database import DirectDatabasePool
from src.shared.litellm_client import LiteLLMClient
from src.shared.sql_loader import load_sql
from src.videos import SQL_DIR

# Trailing window (days) for the attendance facts folded into the profile text
# and the "attended N classes in the last 90 days" clause.
ATTENDANCE_WINDOW_DAYS = 90

# The one bucket-flavor sentence appended per mood bucket. Deterministic v1
# vocabulary matching the five clusters the query generator uses for breadth.
_BUCKET_FLAVOR: dict[MoodBucket, str] = {
    MoodBucket.teach: (
        "wants technique tutorials, drills and progress-appropriate instruction"
    ),
    MoodBucket.enjoy: "wants highlights, funny clips and entertaining montages",
    MoodBucket.inform: (
        "wants news, event results and announcements in this sport"
    ),
    MoodBucket.human: (
        "wants interviews, day-in-the-life and behind-the-scenes with athletes "
        "and coaches"
    ),
    MoodBucket.peak: (
        "wants elite professional performances and championship-level footage"
    ),
}


class MemberVideoProfileService:
    """Lazily build + refresh a member's 5 mood-bucket RAG profiles."""

    def __init__(
        self,
        *,
        db_pool: DirectDatabasePool,
        litellm_client: LiteLLMClient,
        embedding_model: str,
        embedding_dim: int,
        profile_ttl_days: int,
    ) -> None:
        self._db = db_pool
        self._litellm = litellm_client
        self._embedding_model = embedding_model
        self._embedding_dim = embedding_dim
        self._profile_ttl_days = profile_ttl_days

    # ── build (lazy, refresh-on-stale) ────────────────────────────

    async def ensure_profiles(self, member_id: UUID, gym_id: UUID) -> None:
        """Ensure the member's 5 bucket profiles exist and are fresh.

        Raises ``ValueError("Member not found in this gym")`` when the member
        doesn't exist or belongs to a DIFFERENT gym than ``gym_id`` — checked on
        every call (including the freshness no-op), so a caller authorized to
        view a member can never rank another gym's feed by passing a
        mismatched ``gym_id``. Otherwise: no-op when all 5 buckets are present
        and the newest ``built_at`` is younger than ``profile_ttl_days``; else
        (re)builds all 5 — read the member facts, render one deterministic
        text per bucket, embed the batch in one call, and upsert.
        """
        if await self._profiles_fresh(member_id, gym_id):
            return

        source = await self._load_source(member_id, gym_id)
        texts = self._build_texts(source)
        buckets = list(MoodBucket)
        embeddings = await self._litellm.embed(
            texts=[texts[b] for b in buckets],
            model=self._embedding_model,
        )
        self._assert_dims(embeddings)
        await self._upsert(member_id, gym_id, buckets, texts, embeddings)

    async def load_embeddings(self, member_id: UUID) -> dict[MoodBucket, str]:
        """The member's per-bucket profile embeddings (pgvector text form).

        Read after :meth:`ensure_profiles`; each value is passed straight back
        into the candidate query's cosine comparison.
        """
        sql = load_sql(SQL_DIR / "member_profile_embeddings.sql")
        async with self._db.session() as session:
            rows = (
                (await session.execute(text(sql), {"member_id": str(member_id)}))
                .mappings()
                .all()
            )
        return {MoodBucket(r["bucket"]): r["embedding"] for r in rows}

    # ── freshness ─────────────────────────────────────────────────

    async def _profiles_fresh(self, member_id: UUID, gym_id: UUID) -> bool:
        """True when all 5 buckets exist, belong to ``gym_id``, and the newest
        is within the TTL.

        Raises ``ValueError("Member not found in this gym")`` when existing
        profile rows belong to a different gym — every row shares the same
        gym_id (frozen at insert), so checking the first row suffices. No
        rows yet (first-ever request) is not an error here; the cold-build
        path in :meth:`_load_source` owns that check against the live
        ``members`` row.
        """
        sql = load_sql(SQL_DIR / "member_profile_load.sql")
        async with self._db.session() as session:
            rows = (
                (await session.execute(text(sql), {"member_id": str(member_id)}))
                .mappings()
                .all()
            )
        if not rows:
            return False
        if str(rows[0]["gym_id"]) != str(gym_id):
            raise ValueError("Member not found in this gym")
        if len({r["bucket"] for r in rows}) < len(MoodBucket):
            return False
        newest: datetime = max(r["built_at"] for r in rows)
        cutoff = datetime.now(UTC) - timedelta(days=self._profile_ttl_days)
        return newest >= cutoff

    # ── source facts ──────────────────────────────────────────────

    async def _load_source(self, member_id: UUID, gym_id: UUID) -> dict:
        """Read the member facts the deterministic template is built from.

        Raises ``ValueError("Member not found in this gym")`` when the member
        doesn't exist or belongs to a different gym than ``gym_id`` — the
        cold-build-path ownership guard (the freshness path's own guard lives
        in :meth:`_profiles_fresh`).
        """
        sql = load_sql(SQL_DIR / "member_profile_source.sql")
        async with self._db.session() as session:
            row = (
                (
                    await session.execute(
                        text(sql),
                        {
                            "member_id": str(member_id),
                            "window_days": ATTENDANCE_WINDOW_DAYS,
                        },
                    )
                )
                .mappings()
                .fetchone()
            )
        if row is None or str(row["gym_id"]) != str(gym_id):
            raise ValueError("Member not found in this gym")
        return dict(row)

    # ── deterministic text ────────────────────────────────────────

    def _build_texts(self, source: dict) -> dict[MoodBucket, str]:
        """Render the 5 deterministic bucket profile texts from member facts."""
        rank = self._rank_phrase(
            source.get("rank_main_name"), source.get("rank_sub_name")
        )
        disciplines = ", ".join(self._as_list(source.get("disciplines")))
        attendance_count = int(source.get("attendance_count") or 0)
        class_names = self._as_list(source.get("top_classes"))
        base = self._base_sentence(
            rank, disciplines, attendance_count, class_names
        )
        return {
            bucket: f"{base} This member {_BUCKET_FLAVOR[bucket]}."
            for bucket in MoodBucket
        }

    @staticmethod
    def _rank_phrase(main_name: str | None, sub_name: str | None) -> str | None:
        """A member's rank as ``"<main> <sub>"``, or None when unranked."""
        if not main_name:
            return None
        return f"{main_name} {sub_name}".strip()

    @staticmethod
    def _base_sentence(
        rank: str | None,
        disciplines: str,
        attendance_count: int,
        class_names: list[str],
    ) -> str:
        """The shared base sentence, null-safe.

        No rank → "A member"; no disciplines → "at a gym"; zero attendance → the
        attendance clause is omitted entirely.
        """
        subject = f"A {rank} member" if rank else "A member"
        place = f" at a {disciplines} gym" if disciplines else " at a gym"
        sentence = subject + place
        if attendance_count > 0:
            sentence += (
                f", attended {attendance_count} classes in the last "
                f"{ATTENDANCE_WINDOW_DAYS} days"
            )
            if class_names:
                sentence += f", mostly {', '.join(class_names)}"
        return sentence + "."

    # ── persistence ───────────────────────────────────────────────

    async def _upsert(
        self,
        member_id: UUID,
        gym_id: UUID,
        buckets: list[MoodBucket],
        texts: dict[MoodBucket, str],
        embeddings: list[list[float]],
    ) -> None:
        """Upsert all 5 bucket rows in one transaction (executemany)."""
        sql = load_sql(SQL_DIR / "member_profile_upsert.sql")
        params = [
            {
                "member_id": str(member_id),
                "gym_id": str(gym_id),
                "bucket": bucket.value,
                "profile_text": texts[bucket],
                "embedding": self._to_vector_literal(embeddings[i]),
                "embedding_model": self._embedding_model,
            }
            for i, bucket in enumerate(buckets)
        ]
        async with self._db.session() as session, session.begin():
            await session.execute(text(sql), params)

    # ── helpers ───────────────────────────────────────────────────

    def _assert_dims(self, embeddings: list[list[float]]) -> None:
        """Every produced vector must match the pinned embedding dimension.

        The ``vector(1536)`` DDL is a cross-service contract; a mismatch means a
        misconfigured embedding model, so fail loudly rather than write a
        wrong-width vector.
        """
        for vec in embeddings:
            if len(vec) != self._embedding_dim:
                raise ValueError(
                    f"embedding dimension {len(vec)} != expected "
                    f"{self._embedding_dim} (model {self._embedding_model})"
                )

    @staticmethod
    def _to_vector_literal(vec: list[float]) -> str:
        """Serialize a vector to pgvector text form ``'[0.1,0.2,...]'``."""
        return "[" + ",".join(str(x) for x in vec) + "]"

    @staticmethod
    def _as_list(value: object) -> list[str]:
        """A JSONB column as a Python list — tolerant of the driver returning a
        decoded list, a raw JSON string, or NULL."""
        if value is None:
            return []
        if isinstance(value, str):
            return json.loads(value)
        return list(value)  # type: ignore[arg-type]
