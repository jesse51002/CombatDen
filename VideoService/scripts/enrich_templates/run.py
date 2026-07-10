"""One-time PAID run: enrich every unique template video into the RAG sidecar.

    poetry run python -m scripts.enrich_templates.run

Selects the DISTINCT videos referenced by the template feeds (``template_gym_feed``,
both 'good' and 'rejected' verdicts — ~18.9k). For each chunk it BATCH-fetches the
missing transcripts up front (``WorkerEnricher.fetch_chunk_transcripts`` — usually
a no-op, template videos are ~100% cached), then REUSES the worker enricher's
per-video unit (``WorkerEnricher.enrich_one`` — one multimodal
summary+tag+disciplines+facets call, fed the fetched transcript) and embeds
the summary, writing the result to the append-only sidecar
(``video_rag/video_rag.jsonl``). ``scripts/import_yaml`` later loads that sidecar
into ``video_rag`` on every ``make sync-gyms``, so a DB reset reproduces the
enriched templates WITHOUT re-paying the LLM.

This only READS the DB (the pool fields it enriches) and WRITES the sidecar file
— it never mutates the DB. It is resumable/idempotent: videos already in the
sidecar are skipped, so a crashed run just re-runs. Concurrency mirrors the
worker's enrich sweep (``worker_enrich_concurrency``, 8).

Requires a DB already synced (``make sync-gyms`` — the pool + ``template_gym_feed``
present), the keys the configured ``enrich_model`` + ``embedding_model`` use (by
default ``GEMINI_API_KEY`` + ``OPENAI_API_KEY``), and ``APIFY_TOKEN`` for the lazy
transcript fetches of the ~16% of pool videos with no cached transcript. Targets
the DB in ``ENV_FILE`` (default ``.env``).
"""

from __future__ import annotations

import argparse
import asyncio
import logging
import sys
from pathlib import Path

from src.shared.database import DirectDatabasePool
from src.shared.services.llm_client import LiteLLMClient
from src.shared.sql_loader import load_sql
from src.worker.worker_apify import WorkerTranscriptClient
from src.worker.worker_config import settings
from src.worker.worker_cost_log import WorkerCostLog
from src.worker.worker_enricher import WorkerEnricher

from scripts.shared.db_target import build_write_pool
from scripts.shared.video_rag_sidecar import VideoRagRecord, VideoRagSidecar

logger = logging.getLogger(__name__)

# scripts/enrich_templates/run.py -> <root> (holds videos/ and the sidecar).
_DEFAULT_ROOT = Path(__file__).resolve().parent.parent.parent
SQL_DIR = Path(__file__).resolve().parent / "sql"
# Videos summarised per pass == summaries embedded per embed call. Mirrors the
# worker sweep's chunking; also the granularity at which the sidecar is flushed,
# so a crash loses at most one chunk of paid work.
CHUNK_SIZE = 64


class _Totals:
    """Running spend + counts across the run (printed at the end)."""

    def __init__(self) -> None:
        self.processed = 0
        self.enriched = 0
        self.failed = 0
        self.enrich_usd = 0.0
        self.embed_usd = 0.0
        self.transcripts_fetched = 0
        self.actor_starts = 0

    @property
    def transcript_usd(self) -> float:
        return round(
            self.transcripts_fetched
            * settings.apify_transcript_cost_per_transcript_usd
            + self.actor_starts * settings.apify_actor_start_cost_usd,
            4,
        )

    @property
    def total_usd(self) -> float:
        return round(self.enrich_usd + self.embed_usd + self.transcript_usd, 4)


class EnrichTemplatesRunner:
    """Drives the one-time template enrich into the RAG sidecar, reusing the
    worker enricher's per-video unit and appending each chunk as it completes."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        enricher: WorkerEnricher,
        llm: LiteLLMClient,
        sidecar: VideoRagSidecar,
        limit: int | None = None,
    ) -> None:
        self._db = db_pool
        self._enricher = enricher
        self._llm = llm
        self._sidecar = sidecar
        self._limit = limit
        self._vocab = WorkerEnricher.discipline_vocab()

    async def run(self) -> _Totals:
        targets = await self._select_targets()
        totals = _Totals()
        if not targets:
            logger.info("no template videos left to enrich — sidecar is complete")
            return totals
        sem = asyncio.Semaphore(settings.worker_enrich_concurrency)
        for start in range(0, len(targets), CHUNK_SIZE):
            chunk = targets[start : start + CHUNK_SIZE]
            await self._process_chunk(chunk, sem, totals)
            logger.info(
                "  ... %d/%d processed (%d enriched, %d failed) — running $%.2f",
                totals.processed,
                len(targets),
                totals.enriched,
                totals.failed,
                totals.total_usd,
            )
        return totals

    async def _select_targets(self) -> list[dict]:
        """The DISTINCT template videos not yet in the sidecar (resumable skip)."""
        rows = await self._db.fetch_all(load_sql(SQL_DIR / "select_template_videos.sql"))
        done = self._sidecar.existing_ids()
        targets = [row for row in rows if row["video_id"] not in done]
        logger.info(
            "template videos: %d total, %d already enriched, %d to do",
            len(rows),
            len(done),
            len(targets),
        )
        if self._limit is not None and len(targets) > self._limit:
            targets = targets[: self._limit]
            logger.info("  --limit: capped to %d this run (smoke test)", self._limit)
        return targets

    async def _process_chunk(
        self, chunk: list[dict], sem: asyncio.Semaphore, totals: _Totals
    ) -> None:
        """Batch-fetch the chunk's missing transcripts in ONE actor run up front
        (template videos are ~100% cached, so the miss-list is usually empty → no
        run), fan out the vision calls (each fed its transcript), embed the
        successes in one call, and append their records to the sidecar."""
        fetched, starts = await self._enricher.fetch_chunk_transcripts(chunk)
        outcomes = list(
            await asyncio.gather(
                *(
                    self._enricher.enrich_one(
                        video,
                        self._vocab,
                        sem,
                        transcript=self._enricher.effective_transcript(video, fetched),
                    )
                    for video in chunk
                )
            )
        )
        totals.processed += len(outcomes)
        totals.enrich_usd += sum(o.llm_usd for o in outcomes)
        totals.transcripts_fetched += sum(1 for t in fetched.values() if t)
        totals.actor_starts += starts

        rows = [o.row for o in outcomes if o.row is not None]
        totals.failed += sum(1 for o in outcomes if o.row is None)
        if not rows:
            return
        try:
            vectors, embed_usd = await self._llm.embed(
                [row.result.summary for row in rows], model=settings.embedding_model
            )
        except Exception as exc:  # noqa: BLE001 - one embed failure strikes the chunk, not the run
            # Mirror the worker enricher: a batch embed failure (a provider blip,
            # a rate limit, depleted credits) strikes this chunk and the run keeps
            # going. The chunk's videos aren't written to the sidecar, so a later
            # resume re-enriches exactly them (resumable-skip is by sidecar id).
            logger.warning(
                "embed failed for %d row(s) — skipping this chunk: %s", len(rows), exc
            )
            totals.failed += len(rows)
            return
        totals.embed_usd += embed_usd
        records = [
            VideoRagRecord(
                video_id=row.video_id,
                summary=row.result.summary,
                tag=row.result.tag.value,
                disciplines=[d.value for d in row.result.disciplines],
                facets=row.result.facets,
                embedding=vector,
                embedding_model=settings.embedding_model,
            )
            for row, vector in zip(rows, vectors, strict=True)
        ]
        self._sidecar.append(records)
        totals.enriched += len(records)


async def run(*, root: Path, limit: int | None = None) -> _Totals:
    pool = build_write_pool()
    llm = LiteLLMClient(
        timeout_seconds=settings.llm_request_timeout_seconds,
        num_retries=settings.llm_num_retries,
        retry_backoff=settings.llm_retry_backoff_seconds,
    )
    transcript = WorkerTranscriptClient(settings.apify_token)
    enricher = WorkerEnricher(pool, llm, transcript, WorkerCostLog(pool))
    sidecar = VideoRagSidecar(root)
    runner = EnrichTemplatesRunner(pool, enricher, llm, sidecar, limit=limit)
    try:
        totals = await runner.run()
    finally:
        await pool.dispose()
    logger.info(
        "enrich-templates done: %d enriched, %d failed — "
        "enrich $%.2f + embed $%.2f + transcript $%.2f = $%.2f (sidecar: %s)",
        totals.enriched,
        totals.failed,
        totals.enrich_usd,
        totals.embed_usd,
        totals.transcript_usd,
        totals.total_usd,
        sidecar.path,
    )
    return totals


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=_DEFAULT_ROOT)
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Enrich at most N videos this run — a cheap smoke test to prove the "
        "pipeline end-to-end before the full paid run.",
    )
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format="%(message)s")
    asyncio.run(run(root=args.root, limit=args.limit))
    return 0


if __name__ == "__main__":
    sys.exit(main())
