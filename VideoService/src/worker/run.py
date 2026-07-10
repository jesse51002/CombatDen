"""Standalone entrypoint for the VideoService background worker.

    poetry run python -m src.worker.run

An asyncio loop: exit cleanly when the worker is disabled, else call
``WorkerService.run_tick()`` every ``worker_poll_seconds``. A tick that raises is
logged and the loop continues (the lock is released inside the tick's finally).
SIGTERM / SIGINT set the ``stop`` event, which both ends the loop between ticks
AND (passed into ``run_tick``) aborts an in-flight tick at its next ``check_abort``
— so a long enrich/scan/scrape drain is killable mid-drain, not only between ticks.
"""

from __future__ import annotations

import asyncio
import logging
import signal
from contextlib import suppress

from src.shared.database import DirectDatabasePool
from src.shared.services.llm_client import LiteLLMClient
from src.shared.services.resource_lock import ResourceLock
from src.worker.worker_apify import WorkerTranscriptClient
from src.worker.worker_cleanup import WorkerCleanup
from src.worker.worker_config import settings
from src.worker.worker_cost_log import WorkerCostLog
from src.worker.worker_enricher import WorkerEnricher
from src.worker.worker_finalizer import WorkerFinalizer
from src.worker.worker_funnel import WorkerFunnel
from src.worker.worker_scanner import WorkerScanner
from src.worker.worker_scraper import WorkerScraper
from src.worker.worker_service import WorkerService
from src.worker.worker_spec import WorkerSpec
from src.worker.worker_youtube import WorkerYouTubeClient

logger = logging.getLogger(__name__)

# The video_rag.embedding column is vector(3072); the worker MUST embed at this
# dimension or every insert fails. Asserted at startup so a mis-set model /
# embedding_dim is caught immediately, not mid-run.
EXPECTED_EMBEDDING_DIM = 3072


def _build_service(db_pool: DirectDatabasePool) -> WorkerService:
    """Wire the worker's dependencies: one LLM client shared across the steps, the
    YouTube Data API client (discovery + metadata) for the scraper, the Apify
    transcript client (lazy fetch) for the enrich sweep, and the shared cost log."""
    llm = LiteLLMClient()
    lock = ResourceLock(db_pool)
    youtube = WorkerYouTubeClient(settings.youtube_api_key)
    transcript = WorkerTranscriptClient(settings.apify_token)
    cost_log = WorkerCostLog(db_pool)
    return WorkerService(
        db_pool=db_pool,
        resource_lock=lock,
        spec=WorkerSpec(db_pool),
        scraper=WorkerScraper(db_pool, youtube),
        funnel=WorkerFunnel(db_pool, llm),
        enricher=WorkerEnricher(db_pool, llm, transcript, cost_log),
        scanner=WorkerScanner(db_pool, llm, cost_log),
        cleanup=WorkerCleanup(db_pool),
        finalizer=WorkerFinalizer(db_pool),
        cost_log=cost_log,
    )


async def _run_loop(service: WorkerService, stop: asyncio.Event) -> None:
    """Tick until stopped, waiting ``worker_poll_seconds`` (or the stop signal)
    between ticks. A tick exception never kills the loop."""
    logger.info(
        "video worker started (poll %ds)", settings.worker_poll_seconds
    )
    while not stop.is_set():
        try:
            await service.run_tick(stop)
        except Exception:  # noqa: BLE001 - a tick failure must not kill the loop
            logger.error("worker tick raised", exc_info=True)
        with suppress(asyncio.TimeoutError):
            await asyncio.wait_for(
                stop.wait(), timeout=settings.worker_poll_seconds
            )
    logger.info("video worker stopping")


async def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    if not settings.worker_enabled:
        logger.info("worker disabled (worker_enabled=false) — exiting")
        return
    if settings.embedding_dim != EXPECTED_EMBEDDING_DIM:
        raise SystemExit(
            f"embedding_dim {settings.embedding_dim} != {EXPECTED_EMBEDDING_DIM} "
            "(the video_rag.embedding vector column dimension)"
        )

    db_pool = DirectDatabasePool()
    service = _build_service(db_pool)
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, stop.set)
    try:
        await _run_loop(service, stop)
    finally:
        await db_pool.dispose()


if __name__ == "__main__":
    asyncio.run(main())
