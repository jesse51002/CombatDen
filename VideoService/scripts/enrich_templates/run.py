"""One-time PAID run: enrich every unique template video into the RAG sidecar.

    poetry run python -m scripts.enrich_templates.run

Selects the DISTINCT videos referenced by the template feeds (``video_gym_feed``,
both 'good' and 'rejected' verdicts — ~18.9k), then for each REUSES the worker
enricher's per-video unit (``WorkerEnricher.enrich_one`` — one multimodal
summary+tag+disciplines+facets call, lazy Apify transcript on a miss) and embeds
the summary, writing the result to the append-only sidecar
(``video_rag/video_rag.jsonl``). ``scripts/import_yaml`` later loads that sidecar
into ``video_rag`` on every ``make sync-gyms``, so a DB reset reproduces the
enriched templates WITHOUT re-paying the LLM.

This only READS the DB (the pool fields it enriches) and WRITES the sidecar file
— it never mutates the DB. It is resumable/idempotent: videos already in the
sidecar are skipped, so a crashed run just re-runs. Concurrency mirrors the
worker's enrich sweep (``worker_enrich_concurrency``, 8).

Requires a DB already synced (``make sync-gyms`` — the pool + ``video_gym_feed``
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

    @property
    def transcript_usd(self) -> float:
        return round(
            self.transcripts_fetched * settings.apify_transcript_cost_per_video_usd, 4
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
    ) -> None:
        self._db = db_pool
        self._enricher = enricher
        self._llm = llm
        self._sidecar = sidecar
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
        return targets

    async def _process_chunk(
        self, chunk: list[dict], sem: asyncio.Semaphore, totals: _Totals
    ) -> None:
        """Enrich one chunk (fan out the vision calls), embed the successes in one
        call, and append their records to the sidecar."""
        outcomes = list(
            await asyncio.gather(
                *(self._enricher.enrich_one(video, self._vocab, sem) for video in chunk)
            )
        )
        totals.processed += len(outcomes)
        totals.enrich_usd += sum(o.llm_usd for o in outcomes)
        totals.transcripts_fetched += sum(1 for o in outcomes if o.attempted_fetch)

        rows = [o.row for o in outcomes if o.row is not None]
        totals.failed += sum(1 for o in outcomes if o.row is None)
        if not rows:
            return
        vectors, embed_usd = await self._llm.embed(
            [row.result.summary for row in rows], model=settings.embedding_model
        )
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


async def run(*, root: Path) -> _Totals:
    pool = build_write_pool()
    llm = LiteLLMClient()
    transcript = WorkerTranscriptClient(settings.apify_token)
    enricher = WorkerEnricher(pool, llm, transcript, WorkerCostLog(pool))
    sidecar = VideoRagSidecar(root)
    runner = EnrichTemplatesRunner(pool, enricher, llm, sidecar)
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
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format="%(message)s")
    asyncio.run(run(root=args.root))
    return 0


if __name__ == "__main__":
    sys.exit(main())
