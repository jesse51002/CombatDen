"""Enrich sweep — a gym-agnostic pass that gives every un-enriched target video
ONE multimodal classify+summarize+embed and a ``video_rag`` row.

The target set (``worker_enrich_targets.sql``) is every video that still LACKS a
``video_rag`` row and is under the strike ceiling, drawn from each gym's latest
non-failed run (``pending``/``accepted`` rows) ∪ ALL owner-section rows — so it is
NOT tied to any single gym or run. The sweep DRAINS the whole target set: per
video, a single vision call (thumbnail image + title/channel/description +
transcript slice) yields the genre ``tag`` + ``disciplines`` (written onto
``video``) and a ``summary`` + ``facets``; summaries are batch-embedded into
``video_rag``. Targets are processed in chunks (one embed call per chunk), with the
abort flag checked between chunks.

Transcripts are fetched LAZILY and BATCHED: each chunk's cache-MISS videos (rows
with an empty stored ``transcript``) are fetched in ONE Apify actor run BEFORE the
per-video enrich fan-out, and each fetched transcript is passed into
``enrich_one`` AND cached back onto ``video``; a miss/failure degrades to the
placeholder and is NOT a strike.

Strike semantics — HARD errors only: a video whose multimodal call OR whose chunk's
embed call raises gets ``failure_count += 1`` (``worker_bump_failure.sql``) and is
skipped; a video that enriches successfully gets ``failure_count`` reset to 0
(``worker_reset_failure.sql``). A missing transcript is not an error. Spend is
logged as POOL-LEVEL cost rows (gym_id / run_id NULL) once at the end.

Thumbnail fallback: the pool's stored ``thumbnail_url`` is whatever resolution the
scrape found (``worker_transforms._best_thumbnail`` prefers YouTube's ``maxres``
variant), but ``maxresdefault`` only exists for HD uploads — an older/non-HD video
404s on it, which litellm surfaces as an image-fetch ``BadRequestError`` on the
multimodal call. YouTube always serves ``hqdefault`` for a live video, so a call
that fails on the stored thumbnail is retried ONCE against the constructed
``hqdefault`` URL before the video is struck (see ``enrich_one``).
"""

from __future__ import annotations

import asyncio
import json
import logging
from collections.abc import Iterator, Sequence
from dataclasses import dataclass
from pathlib import Path
from string import Template

from schema.gym_type import GymType
from src.shared.database import DirectDatabasePool
from src.shared.interfaces.llm_client import LLMClient
from src.shared.sql_loader import load_sql
from src.shared.util.duration import format_duration
from src.worker.schema.enrich_result import EnrichResult
from src.worker.worker_abort import check_abort
from src.worker.worker_apify import WorkerTranscriptClient
from src.worker.worker_config import settings
from src.worker.worker_cost_log import WorkerCostLog

logger = logging.getLogger(__name__)

SQL_DIR = Path(__file__).resolve().parent / "sql"
ENRICH_PROMPT_PATH = Path(__file__).resolve().parent / "prompts" / "worker_enrich.md"

# Videos per sweep chunk == texts per embed call == the transcript batch fetched
# up front per chunk. The provider caps batch size / tokens; 64 short summaries
# per call keeps well under it while amortising the request overhead. Also the
# granularity at which the abort flag is checked.
EMBED_BATCH_SIZE = 64
NO_TRANSCRIPT_PLACEHOLDER = (
    "(no transcript available — judge from the title, description, and thumbnail)"
)
# YouTube always serves this resolution for a live video (unlike ``maxresdefault``,
# which 404s for non-HD uploads) — the enrich fallback thumbnail, and the primary
# when the pool row has no stored ``thumbnail_url`` at all.
HQDEFAULT_THUMBNAIL_URL = "https://i.ytimg.com/vi/{video_id}/hqdefault.jpg"
# Substring of litellm's image-fetch ``BadRequestError`` message (e.g. "Unable to
# fetch image from URL. Status code: 404 ...maxresdefault.jpg"). ``LiteLLMClient``
# wraps every provider exception in ``ProviderError``, losing the original type but
# keeping its message, so the marker is matched against the stringified error.
IMAGE_FETCH_ERROR_MARKER = "Unable to fetch image"


@dataclass(frozen=True)
class EnrichResultRow:
    """A successful enrichment paired with its source video id."""

    video_id: str
    result: EnrichResult


@dataclass(frozen=True)
class EnrichOutcome:
    """One video's enrich attempt: the row (None when the multimodal call failed)
    and the LLM spend. Transcript fetching is now a per-chunk batch upstream, so
    the fetch bookkeeping no longer rides on the per-video outcome."""

    video_id: str
    row: EnrichResultRow | None
    llm_usd: float


@dataclass
class _SweepTotals:
    """Running spend + counts accumulated across the sweep's chunks."""

    processed: int = 0
    enriched: int = 0
    enrich_usd: float = 0.0
    embed_usd: float = 0.0
    # Transcripts actually returned by the batch fetches (billed per transcript).
    transcripts_fetched: int = 0
    # Batched actor runs actually started (billed per start).
    actor_starts: int = 0


class WorkerEnricher:
    """Drains the un-enriched target set: one multimodal enrich + embed per video,
    fetching missing transcripts lazily, striking hard failures."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        llm_client: LLMClient,
        transcript_client: WorkerTranscriptClient,
        cost_log: WorkerCostLog,
    ) -> None:
        self._db = db_pool
        self._llm = llm_client
        self._transcript = transcript_client
        self._cost_log = cost_log

    async def drain(self, abort: asyncio.Event) -> bool:
        """Enrich every target. Returns True iff there was work this sweep."""
        targets = await self._db.fetch_all(
            load_sql(SQL_DIR / "worker_enrich_targets.sql"),
            {"max_failures": settings.worker_failure_max},
        )
        if not targets:
            return False

        vocab = self.discipline_vocab()
        sem = asyncio.Semaphore(settings.worker_enrich_concurrency)
        totals = _SweepTotals()
        for chunk in self._chunks(targets, EMBED_BATCH_SIZE):
            check_abort(abort)
            await self._process_chunk(chunk, vocab, sem, totals)

        transcript_usd = round(
            totals.transcripts_fetched
            * settings.apify_transcript_cost_per_transcript_usd
            + totals.actor_starts * settings.apify_actor_start_cost_usd,
            4,
        )
        await self._cost_log.log_enrich(
            transcript_usd=transcript_usd,
            enrich_usd=totals.enrich_usd,
            embed_usd=totals.embed_usd,
            videos=totals.processed,
            transcripts_fetched=totals.transcripts_fetched,
            actor_starts=totals.actor_starts,
        )
        logger.info(
            "enrich sweep: %d processed, %d enriched, %d transcripts fetched",
            totals.processed,
            totals.enriched,
            totals.transcripts_fetched,
        )
        return True

    async def _process_chunk(
        self,
        chunk: list[dict],
        vocab: str,
        sem: asyncio.Semaphore,
        totals: _SweepTotals,
    ) -> None:
        """Enrich one chunk: batch-fetch the chunk's missing transcripts in ONE
        actor run up front, fan out the vision calls (each fed its transcript),
        cache the fetched transcripts, embed the successes in one call, then strike
        / heal the video rows."""
        fetched, starts = await self.fetch_chunk_transcripts(chunk)
        outcomes = list(
            await asyncio.gather(
                *(
                    self.enrich_one(
                        v,
                        vocab,
                        sem,
                        transcript=self.effective_transcript(v, fetched),
                    )
                    for v in chunk
                )
            )
        )
        await self._cache_transcripts(fetched)
        totals.processed += len(outcomes)
        totals.enrich_usd += sum(o.llm_usd for o in outcomes)
        totals.transcripts_fetched += sum(1 for t in fetched.values() if t)
        totals.actor_starts += starts

        rows = [o.row for o in outcomes if o.row is not None]
        struck = [o.video_id for o in outcomes if o.row is None]
        if rows:
            await self._write_tags(rows)
            try:
                totals.embed_usd += await self._embed_and_store(rows)
            except Exception as exc:  # noqa: BLE001 - embed failure strikes chunk
                logger.warning(
                    "embed failed for chunk — striking %d video(s): %s",
                    len(rows),
                    exc,
                )
                struck += [r.video_id for r in rows]
            else:
                totals.enriched += len(rows)
                await self._reset_failure([r.video_id for r in rows])
        if struck:
            await self._bump_failure(struck)

    async def enrich_one(
        self,
        video: dict,
        vocab: str,
        sem: asyncio.Semaphore,
        *,
        transcript: str | None,
    ) -> EnrichOutcome:
        """One video's enrich call under the gate. The transcript is RECEIVED (the
        caller batch-fetches a chunk's misses up front via
        ``fetch_chunk_transcripts`` and passes each in via ``effective_transcript``
        — the cached one, the freshly-fetched one, or None → the placeholder); this
        unit never fetches. A failed multimodal call never aborts the sweep (it
        becomes a strike upstream).

        The stored ``thumbnail_url`` is the primary image (constructed
        ``hqdefault`` when the pool row has none at all). When the multimodal call
        fails because litellm couldn't fetch that image — the stored
        ``maxresdefault`` 404s for a non-HD upload — the call is retried ONCE
        against the constructed ``hqdefault`` URL, which YouTube always serves.
        Only a failure of that retry (or a non-image-fetch failure) strikes the
        video.

        This is the PUBLIC per-video enrich unit — the sweep drives it in chunks,
        and the one-time ``scripts/enrich_templates`` run reuses it to produce the
        template RAG sidecar (same summary pass, sidecar sink instead of the DB).
        ``video`` needs the keys ``video_id``, ``title``, ``channel_name``,
        ``description``, ``thumbnail_url``, ``duration_seconds``, ``transcript``."""
        async with sem:
            video_id = video["video_id"]
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
            messages = [{"role": "user", "content": prompt}]
            hqdefault_url = self._hqdefault_url(video_id)
            thumbnail_url = video["thumbnail_url"] or hqdefault_url

            try:
                result, cost = await self._llm.complete_structured_with_cost(
                    messages,
                    schema=EnrichResult,
                    model=settings.enrich_model,
                    image_urls=self._image_urls(thumbnail_url),
                )
            except Exception as exc:  # noqa: BLE001 - retried once below, else a strike
                if not (
                    self._is_image_fetch_error(exc) and thumbnail_url != hqdefault_url
                ):
                    logger.warning(
                        "enrich failed for %s (strike): %s", video_id, exc
                    )
                    return self._struck(video_id)

                logger.info(
                    "enrich %s: thumbnail fetch failed on %s — retrying with "
                    "hqdefault fallback",
                    video_id,
                    thumbnail_url,
                )
                try:
                    result, cost = await self._llm.complete_structured_with_cost(
                        messages,
                        schema=EnrichResult,
                        model=settings.enrich_model,
                        image_urls=self._image_urls(hqdefault_url),
                    )
                except Exception as retry_exc:  # noqa: BLE001 - hqdefault also failed
                    logger.warning(
                        "enrich failed for %s (strike, hqdefault retry also "
                        "failed): %s",
                        video_id,
                        retry_exc,
                    )
                    return self._struck(video_id)

            return EnrichOutcome(
                video_id=video_id,
                row=EnrichResultRow(video_id, result),
                llm_usd=cost,
            )

    async def fetch_chunk_transcripts(
        self, videos: list[dict]
    ) -> tuple[dict[str, str | None], int]:
        """Batch-fetch transcripts for a chunk's cache-MISS videos (rows with an
        empty stored ``transcript``) in one actor run per ``apify_transcript_batch_size``
        slice. Returns ``(video_id -> fetched-transcript-or-None for the misses,
        number of actor runs started)``. No misses → no run, 0 starts (so a
        ~100%-cached template chunk pays nothing). Public so the enrich-templates
        run reuses the exact miss-detection + batching + start-count logic."""
        misses = [v["video_id"] for v in videos if not self._has_transcript(v)]
        fetched: dict[str, str | None] = {}
        starts = 0
        size = settings.apify_transcript_batch_size
        for start in range(0, len(misses), size):
            batch = misses[start : start + size]
            fetched.update(await self._transcript.fetch_batch(batch))
            starts += 1
        return fetched, starts

    @staticmethod
    def effective_transcript(
        video: dict, fetched: dict[str, str | None]
    ) -> str | None:
        """The transcript to enrich ``video`` with: its cached one if present, else
        the batch's freshly-fetched one (which may be None → the placeholder)."""
        cached = video["transcript"]
        if cached and str(cached).strip():
            return cached
        return fetched.get(video["video_id"])

    @staticmethod
    def _has_transcript(video: dict) -> bool:
        """Whether the pool row already carries a usable cached transcript."""
        transcript = video["transcript"]
        return bool(transcript and str(transcript).strip())

    async def _cache_transcripts(self, fetched: dict[str, str | None]) -> None:
        """Persist every transcript we actually fetched onto its pool video, so a
        later sweep reuses it instead of re-paying Apify."""
        params = [
            {"video_id": vid, "transcript": transcript}
            for vid, transcript in fetched.items()
            if transcript
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
        """Batch-embed the chunk's summaries and insert the ``video_rag`` rows.

        Raised by the embed call on a provider failure — the caller strikes the
        chunk's videos so they are retried on a later sweep."""
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

    async def _reset_failure(self, video_ids: list[str]) -> None:
        """Clear the strike counter on videos that enriched successfully."""
        if not video_ids:
            return
        await self._db.execute_with_retry(
            load_sql(SQL_DIR / "worker_reset_failure.sql"),
            [{"video_id": vid} for vid in video_ids],
        )

    async def _bump_failure(self, video_ids: list[str]) -> None:
        """Bump the strike counter on videos whose enrich hard-failed."""
        if not video_ids:
            return
        await self._db.execute_with_retry(
            load_sql(SQL_DIR / "worker_bump_failure.sql"),
            [{"video_id": vid} for vid in video_ids],
        )

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
    def _hqdefault_url(video_id: str) -> str:
        """The always-available ``hqdefault`` YouTube thumbnail URL for
        ``video_id`` — the enrich fallback (see module docstring)."""
        return HQDEFAULT_THUMBNAIL_URL.format(video_id=video_id)

    @staticmethod
    def _is_image_fetch_error(exc: Exception) -> bool:
        """Whether a failed multimodal call was litellm choking on fetching the
        thumbnail image (vs. a genuine provider/schema failure), matched against
        the stringified error since ``LiteLLMClient`` wraps every litellm
        exception in ``ProviderError``."""
        return IMAGE_FETCH_ERROR_MARKER in str(exc)

    @staticmethod
    def _struck(video_id: str) -> EnrichOutcome:
        """The strike outcome for a video whose enrich call(s) failed — no row,
        no spend billed for this failed attempt."""
        return EnrichOutcome(video_id=video_id, row=None, llm_usd=0.0)

    @staticmethod
    def _vector_literal(vector: list[float]) -> str:
        """A float list as the pgvector text form ``[f1,f2,...]``."""
        return "[" + ",".join(repr(float(f)) for f in vector) + "]"

    @staticmethod
    def discipline_vocab() -> str:
        """The allowed discipline values as a bulleted list, built from the enum
        so the prompt can never drift from the schema. Public so a reuser (the
        enrich-templates run) builds the exact ``vocab`` arg ``enrich_one`` wants."""
        return "\n".join(f"  - {member.value}" for member in GymType)

    @staticmethod
    def _chunks(seq: Sequence[dict], size: int) -> Iterator[list[dict]]:
        """Yield ``seq`` in lists of at most ``size``."""
        for start in range(0, len(seq), size):
            yield list(seq[start : start + size])
