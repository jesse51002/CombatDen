"""Stage 4 — enrich candidates + owner videos with ONE multimodal call each.

The enrich set is the budgeted candidates ∪ the gym's owner-section videos, minus
those already enriched (a ``video_rag`` row). Per video, a single vision call
(thumbnail image + title/channel/description + transcript slice) yields the genre
``tag`` + ``disciplines`` (written onto ``video``) and a ``summary`` + ``facets``;
the summaries are then batch-embedded and stored in ``video_rag``. Per-video
failures are isolated (skip + count), never aborting the run; calls fan out under
a concurrency gate.

Transcripts are fetched LAZILY here: a candidate whose pool row has no cached
transcript triggers one Apify transcript-actor run (under the same gate), the
result feeds this video's prompt AND is cached back onto ``video`` so a later run
reuses it instead of re-paying Apify. A transcript miss/failure degrades to the
no-transcript placeholder — it never aborts the video's enrich or the run.
"""

from __future__ import annotations

import asyncio
import json
import logging
from dataclasses import dataclass
from pathlib import Path
from string import Template

from schema.gym_type import GymType
from src.shared.database import DirectDatabasePool
from src.shared.interfaces.llm_client import LLMClient
from src.shared.sql_loader import load_sql
from src.shared.util.duration import format_duration
from src.worker.schema.enrich_result import EnrichResult
from src.worker.worker_apify import WorkerTranscriptClient
from src.worker.worker_config import settings

logger = logging.getLogger(__name__)

SQL_DIR = Path(__file__).resolve().parent / "sql"
ENRICH_PROMPT_PATH = Path(__file__).resolve().parent / "prompts" / "worker_enrich.md"

# Texts per embedding call. The provider caps batch size / tokens; 64 short
# summaries per call keeps well under it while amortising the request overhead.
EMBED_BATCH_SIZE = 64
# Language requested from the transcript actor for the lazy fetch.
TRANSCRIPT_LANGUAGE = "en"
NO_TRANSCRIPT_PLACEHOLDER = (
    "(no transcript available — judge from the title, description, and thumbnail)"
)


@dataclass(frozen=True)
class EnrichResultRow:
    """A successful enrichment paired with its source video id."""

    video_id: str
    result: EnrichResult


@dataclass(frozen=True)
class EnrichOutcome:
    """One video's enrich attempt: the row (None when the LLM call failed), the
    LLM spend, whether a transcript fetch was attempted (billable), and the
    transcript actually fetched (to cache), if any."""

    video_id: str
    row: EnrichResultRow | None
    llm_usd: float
    attempted_fetch: bool
    fetched_transcript: str | None


@dataclass(frozen=True)
class EnrichCost:
    """What the enrich stage did: spend (LLM + embed + transcript) + row counts."""

    llm_usd: float = 0.0
    embed_usd: float = 0.0
    transcript_usd: float = 0.0
    enriched_count: int = 0
    skipped_count: int = 0


class WorkerEnricher:
    """Runs the one-call classify+summarize+embed over the enrich set, fetching
    missing transcripts lazily."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        llm_client: LLMClient,
        transcript_client: WorkerTranscriptClient,
    ) -> None:
        self._db = db_pool
        self._llm = llm_client
        self._transcript = transcript_client

    async def enrich(self, gym_id: str, candidate_ids: list[str]) -> EnrichCost:
        """Enrich the candidates + owner videos that are not yet enriched."""
        to_enrich = await self._resolve_targets(gym_id, candidate_ids)
        if not to_enrich:
            return EnrichCost()
        videos = await self._db.fetch_all(
            load_sql(SQL_DIR / "worker_load_videos_for_enrich.sql"),
            {"ids": to_enrich},
        )
        outcomes = await self._enrich_all(videos)
        llm_usd = sum(o.llm_usd for o in outcomes)
        fetch_count = sum(1 for o in outcomes if o.attempted_fetch)
        transcript_usd = round(
            fetch_count * settings.apify_transcript_cost_per_video_usd, 4
        )
        await self._cache_transcripts(outcomes)

        rows = [o.row for o in outcomes if o.row is not None]
        skipped = sum(1 for o in outcomes if o.row is None)
        if not rows:
            logger.info(
                "gym %s enrich: 0 enriched, %d skipped, %d transcripts fetched; "
                "transcript $%.4f",
                gym_id,
                skipped,
                fetch_count,
                transcript_usd,
            )
            return EnrichCost(
                llm_usd=llm_usd,
                transcript_usd=transcript_usd,
                skipped_count=skipped,
            )

        await self._write_tags(rows)
        embed_usd = await self._embed_and_store(rows)
        logger.info(
            "gym %s enrich: %d enriched, %d skipped, %d transcripts fetched; "
            "LLM $%.4f embed $%.4f transcript $%.4f",
            gym_id,
            len(rows),
            skipped,
            fetch_count,
            llm_usd,
            embed_usd,
            transcript_usd,
        )
        return EnrichCost(
            llm_usd=llm_usd,
            embed_usd=embed_usd,
            transcript_usd=transcript_usd,
            enriched_count=len(rows),
            skipped_count=skipped,
        )

    async def _resolve_targets(
        self, gym_id: str, candidate_ids: list[str]
    ) -> list[str]:
        """Candidates ∪ owner videos, minus those already enriched."""
        owner = await self._db.fetch_all(
            load_sql(SQL_DIR / "worker_owner_feed_ids.sql"), {"gym_id": gym_id}
        )
        combined = list(
            dict.fromkeys(candidate_ids + [r["video_id"] for r in owner])
        )
        if not combined:
            return []
        already = await self._db.fetch_all(
            load_sql(SQL_DIR / "worker_existing_rag_ids.sql"), {"ids": combined}
        )
        enriched = {r["video_id"] for r in already}
        return [vid for vid in combined if vid not in enriched]

    async def _enrich_all(self, videos: list[dict]) -> list[EnrichOutcome]:
        """Fan out the per-video enrich calls; return every outcome."""
        vocab = self._discipline_vocab()
        sem = asyncio.Semaphore(settings.worker_enrich_concurrency)
        return list(
            await asyncio.gather(*(self._enrich_one(v, vocab, sem) for v in videos))
        )

    async def _enrich_one(
        self, video: dict, vocab: str, sem: asyncio.Semaphore
    ) -> EnrichOutcome:
        """One video's enrich call under the gate, fetching its transcript lazily
        if the pool row has none. A fetch miss/failure or a failed LLM call never
        aborts the run."""
        async with sem:
            video_id = video["video_id"]
            transcript = video["transcript"]
            attempted_fetch = False
            fetched: str | None = None
            if not transcript or not str(transcript).strip():
                attempted_fetch = True
                fetched = await self._transcript.fetch(
                    video_id, language=TRANSCRIPT_LANGUAGE
                )
                transcript = fetched

            prompt = Template(
                ENRICH_PROMPT_PATH.read_text(encoding="utf-8")
            ).safe_substitute(
                title=video["title"],
                channel=video["channel_name"],
                description=video["description"],
                duration=format_duration(video["duration_seconds"]),
                transcript=self._truncate(transcript),
                gym_type_vocab=vocab,
            )
            try:
                result, cost = await self._llm.complete_structured_with_cost(
                    [{"role": "user", "content": prompt}],
                    schema=EnrichResult,
                    model=settings.enrich_model,
                    image_urls=self._image_urls(video["thumbnail_url"]),
                )
            except Exception as exc:  # noqa: BLE001 - one bad video never aborts
                logger.warning(
                    "enrich failed for %s (skipped): %s", video_id, exc
                )
                return EnrichOutcome(
                    video_id=video_id,
                    row=None,
                    llm_usd=0.0,
                    attempted_fetch=attempted_fetch,
                    fetched_transcript=fetched,
                )
            return EnrichOutcome(
                video_id=video_id,
                row=EnrichResultRow(video_id, result),
                llm_usd=cost,
                attempted_fetch=attempted_fetch,
                fetched_transcript=fetched,
            )

    async def _cache_transcripts(self, outcomes: list[EnrichOutcome]) -> None:
        """Persist every transcript we actually fetched this run onto its pool
        video, so a later run reuses it instead of re-paying Apify."""
        params = [
            {"video_id": o.video_id, "transcript": o.fetched_transcript}
            for o in outcomes
            if o.fetched_transcript
        ]
        if not params:
            return
        await self._db.execute_with_retry(
            load_sql(SQL_DIR / "worker_cache_transcripts.sql"), params
        )

    async def _write_tags(self, rows: list[EnrichResultRow]) -> None:
        """Write each enrichment's genre + disciplines onto its pool video."""
        params = [
            {
                "video_id": row.video_id,
                "tag": row.result.tag.value,
                "disciplines": json.dumps(
                    [d.value for d in row.result.disciplines]
                ),
            }
            for row in rows
        ]
        await self._db.execute_with_retry(
            load_sql(SQL_DIR / "worker_update_video_tags.sql"), params
        )

    async def _embed_and_store(self, rows: list[EnrichResultRow]) -> float:
        """Batch-embed the summaries and insert the ``video_rag`` rows."""
        summaries = [row.result.summary for row in rows]
        vectors: list[list[float]] = []
        embed_usd = 0.0
        for start in range(0, len(summaries), EMBED_BATCH_SIZE):
            batch = summaries[start : start + EMBED_BATCH_SIZE]
            batch_vectors, cost = await self._llm.embed(
                batch, model=settings.embedding_model
            )
            vectors.extend(batch_vectors)
            embed_usd += cost

        params = [
            {
                "video_id": row.video_id,
                "summary": row.result.summary,
                "facets": json.dumps(row.result.facets),
                "embedding": self._vector_literal(vector),
                "embedding_model": settings.embedding_model,
            }
            for row, vector in zip(rows, vectors, strict=True)
        ]
        await self._db.execute_with_retry(
            load_sql(SQL_DIR / "worker_insert_video_rag.sql"), params
        )
        return embed_usd

    def _truncate(self, text: str | None) -> str:
        """Transcript head clipped to the enrich budget, or the placeholder."""
        if not text or not text.strip():
            return NO_TRANSCRIPT_PLACEHOLDER
        text = text.strip()
        budget = settings.enrich_transcript_char_budget
        if len(text) <= budget:
            return text
        return text[:budget].rstrip() + "\n…(transcript truncated)"

    @staticmethod
    def _image_urls(thumbnail_url: str | None) -> list[str] | None:
        """The thumbnail as a one-item image list when it is a plausible http(s)
        URL, else None (a text-only call)."""
        if thumbnail_url and thumbnail_url.startswith(("http://", "https://")):
            return [thumbnail_url]
        return None

    @staticmethod
    def _vector_literal(vector: list[float]) -> str:
        """A float list as the pgvector text form ``[f1,f2,...]``."""
        return "[" + ",".join(repr(float(f)) for f in vector) + "]"

    @staticmethod
    def _discipline_vocab() -> str:
        """The allowed discipline values as a bulleted list, built from the enum
        so the prompt can never drift from the schema."""
        return "\n".join(f"  - {member.value}" for member in GymType)
