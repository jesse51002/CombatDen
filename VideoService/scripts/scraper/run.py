"""Scrape the shared video pool and classify it — one run, two stages.

    poetry run python -m scripts.scraper.run                 # every gym's queries
    poetry run python -m scripts.scraper.run --gym-id vinyasa  # one gym's queries

The search queries live ON THE GYMS (``gyms/<id>.yaml`` -> ``videos.queries``) —
each gym owns the searches that populate its slice of the pool. This script:

1. **Scrape** — gather the union of the gyms' queries and run them through one
   Apify actor (``streamers/youtube-scraper``) that does the whole fetch: search +
   metadata + channel avatar + the transcript inline. De-dups across queries and
   **replaces** the shared pool (``videos/``) — videos arrive WITH transcripts.
2. **Classify** — one LLM call per pooled video assigns its genre (``tag``) and
   the disciplines it is relevant to (``gym_type``), from the video's real
   content. This pass is **gym-agnostic**: it makes NO approval decision. Whether
   a gym shows a video is the separate per-gym scan (``scripts.scan.run``), which
   reads these ``gym_type`` tags to pick its candidate slice.

Reads ``APIFY_TOKEN`` (scrape) and the tagging model key (e.g. ``GEMINI_API_KEY``,
classify) from env / `.env`. Appends a SEARCH and a TAG entry to ``cost_log.yaml``.
Run ONE pipeline job at a time — providers are rate-limited (never parallel).
"""

from __future__ import annotations

import argparse
import asyncio
import functools
import itertools
import logging
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path

from schema.cost_log import CostEntry, ExecutionType
from schema.video_classification import VideoClassification
from schema.video_output import VideoOutput
from scripts.scraper.client import ApifyYouTubeSearchClient
from scripts.scraper.config import apify_search_settings
from scripts.scraper.transform import ApifyHit, build_outputs, parse_search_items
from src.api.service.videos_service import VideosService
from src.classification.video_classifier import (
    VIDEO_CLASSIFY_MODEL,
    VideoClassifier,
    format_duration,
)
from src.core.errors import ProviderError, SchemaValidationError
from src.shared.services.llm_client import LiteLLMClient
from src.shared.util.video_id import video_id_from_url

logger = logging.getLogger(__name__)

# scripts/scraper/run.py -> <root> (the single-tenant data root, holds gyms/ etc.)
_DEFAULT_ROOT = Path(__file__).resolve().parent.parent.parent
DEFAULT_MAX_RESULTS = 50
DEFAULT_LANG = "en"
# streamers/youtube-scraper pricing, ~$2.40 / 1,000 videos (live as of 2026-05;
# re-verify on the actor page). Used to estimate the scrape's Apify spend.
APIFY_USD_PER_VIDEO = 0.0024
# Max videos tagged at once. 16 tripped Gemini Flash-Lite's rate limit on a big
# fan-out (~800 RateLimitErrors over ~5.6k calls); 8 keeps the request rate under
# the limit (with LLM_NUM_RETRIES riding out any stragglers).
CONCURRENCY = 8
# Apify actor runs fired at once during fetch — one run per query. The cap is MEMORY:
# each youtube-scraper run needs 1024MB, so the ceiling is (actor-memory pool)/1024MB.
# On the 32GB plan (32 max workers) that's 32768/1024 = 32. (Was 8 on the old 8GB plan;
# exceeding the pool fails the surplus runs with "exceed the memory limit" — but the
# per-query try/except drops just those, never the whole batch.) Runs are independent
# and transform.build_outputs is order-independent, so concurrency only changes speed,
# never the resulting pool.
FETCH_CONCURRENCY = 32


# --- queries -----------------------------------------------------------------


async def _queries(service: VideosService, gym_id: str | None) -> list[str]:
    """The union of the gyms' ``videos.queries`` (one gym if ``gym_id`` given),
    order-preserving + deduped."""
    gym_ids = [gym_id] if gym_id is not None else await service.list_gyms()
    out: list[str] = []
    seen: set[str] = set()
    for gid in gym_ids:
        gym = await service.load_gym(gid)
        for q in gym.videos.queries:
            if q not in seen:
                seen.add(q)
                out.append(q)
    return out


# --- classify ----------------------------------------------------------------


def _apply(video: VideoOutput, verdict: VideoClassification) -> VideoOutput:
    """A copy of ``video`` carrying the pool tags (genre + disciplines)."""
    return video.model_copy(update={"tag": verdict.tag, "gym_type": verdict.gym_type})


def _untagged(video: VideoOutput) -> VideoOutput:
    """A copy of ``video`` left untagged (no genre, no disciplines), so it is a
    candidate for no gym until re-tagged — for no-transcript or failed videos."""
    return video.model_copy(update={"tag": None, "gym_type": []})


def _has_transcript(video: VideoOutput) -> bool:
    return bool(video.transcript and video.transcript.strip())


async def _tag_one(
    classifier: VideoClassifier,
    video: VideoOutput,
    model: str,
    sem: asyncio.Semaphore,
    total: int,
    counter: "itertools.count[int]",
    started: float,
) -> tuple[VideoOutput, bool]:
    """Tag one video under the concurrency gate. Returns (video, failed?)."""
    async with sem:
        t0 = time.monotonic()
        try:
            verdict = await classifier.classify(video, model=model)
            now = time.monotonic()
            done = next(counter)
            logger.info(
                "[%d/%d] %s\n    length:   %s\n    tag:      %s\n    gym_type: %s\n"
                "    req: %.1fs · avg: %.1fs ×%d workers\n",
                done,
                total,
                video.title,
                format_duration(video.duration_seconds),
                verdict.tag.value,
                [g.value for g in verdict.gym_type],
                now - t0,
                (now - started) / done,
                CONCURRENCY,
            )
            return _apply(video, verdict), False
        except (SchemaValidationError, ProviderError) as exc:
            done = next(counter)
            logger.warning(
                "[%d/%d] %s\n    tag FAILED (left untagged): %s\n",
                done,
                total,
                video.title,
                exc,
            )
            return _untagged(video), True


# --- run ---------------------------------------------------------------------


def _is_tagged(video: VideoOutput) -> bool:
    """Whether the classify pass has already judged this video. A tag is only ever
    set together with gym_type, and a tag-failure / no-transcript video keeps
    ``tag=None`` — so ``tag is not None`` cleanly means "already classified" and is
    the incremental gate (re-runs skip it; failures, still None, get retried)."""
    return video.tag is not None


def _merge_into_pool(
    existing: list[VideoOutput], fresh: list[VideoOutput]
) -> tuple[list[VideoOutput], list[VideoOutput], int]:
    """Dedup ``fresh`` (already deduped within the scrape) against the ``existing``
    pool by video id. A genuinely new video is added untagged. A video already in
    the pool is KEPT (its tag / gym_type / transcript preserved — never retagged);
    we only union the queries that surfaced it and keep the best (lowest)
    relevance, and adopt a transcript if it had none before.

    Returns ``(merged_pool, to_persist, new_count)`` where ``to_persist`` is just
    the new + changed records to write (untouched videos aren't rewritten)."""
    by_id: dict[str, VideoOutput] = {
        video_id_from_url(v.url): v for v in existing
    }
    to_persist: list[VideoOutput] = []
    new_count = 0
    for v in fresh:
        vid = video_id_from_url(v.url)
        cur = by_id.get(vid)
        if cur is None:
            by_id[vid] = v  # new -> added untagged
            to_persist.append(v)
            new_count += 1
            continue
        merged_queries = list(dict.fromkeys([*cur.source_queries, *v.source_queries]))
        relevance = min(cur.relevance_index, v.relevance_index)
        transcript = cur.transcript or v.transcript
        transcript_error = cur.transcript_error if cur.transcript else v.transcript_error
        if (
            merged_queries != cur.source_queries
            or relevance != cur.relevance_index
            or transcript != cur.transcript
        ):
            updated = cur.model_copy(
                update={
                    "source_queries": merged_queries,
                    "relevance_index": relevance,
                    "transcript": transcript,
                    "transcript_error": transcript_error,
                }
            )
            by_id[vid] = updated
            to_persist.append(updated)  # changed metadata, but tag preserved
    return list(by_id.values()), to_persist, new_count


async def scrape_pool(
    service: VideosService,
    *,
    gym_id: str | None,
    lang: str,
    max_results: int,
    fetch_concurrency: int = FETCH_CONCURRENCY,
    queries: list[str] | None = None,
) -> None:
    """Stage 1: fetch the gyms' queries from Apify and MERGE the results into the
    pool (never wipes — so scraping one gym can't destroy others' videos, and
    existing tags survive). New videos are deduped against the pool by id and
    added untagged; videos already present keep their tag and only gain the new
    query / better relevance. Logs SEARCH cost.

    Decoupled from classify: it only writes the pool. Classify is a separate pass
    that reads the pool from disk and tags whatever is still untagged — the two
    stages never hand videos to each other.

    Apify still runs every query (it can't fetch "only what's new"), so the Apify
    cost is the full fetch; the saving is that tagging only touches new videos."""
    if queries is None:
        queries = await _queries(service, gym_id)
    else:
        # An explicit list (e.g. retrying queries an Apify limit dropped) — dedup,
        # drop blanks, preserve order. Bypasses the per-gym union entirely.
        queries = list(dict.fromkeys(q.strip() for q in queries if q.strip()))
    if not queries:
        logger.warning(
            "no queries%s — add videos.queries to gyms (or pass --queries-file); "
            "nothing to scrape",
            f" for gym {gym_id!r}" if gym_id else "",
        )
        return
    client = ApifyYouTubeSearchClient(apify_search_settings().apify_token)
    workers = max(1, min(fetch_concurrency, len(queries)))
    loop = asyncio.get_running_loop()
    done = itertools.count(1)

    async def _search(i: int, query: str, pool: ThreadPoolExecutor) -> list[ApifyHit]:
        """One query's Apify run, off the event loop so the runs overlap. The
        blocking client.call() goes to the thread pool; parsing stays here. One
        query's failure must NOT abort the whole batch (and waste the Apify spend on
        the queries that already succeeded), so we log it and drop just that query."""
        logger.info("[%d/%d] searching: %s", i, len(queries), query)
        try:
            items = await loop.run_in_executor(
                pool,
                functools.partial(client.search, query, max_results=max_results, language=lang),
            )
        except Exception as exc:  # noqa: BLE001 — one bad query must not kill the run
            logger.warning(
                "[%d/%d] search FAILED (dropped): %s\n    %s",
                i, len(queries), query, exc,
            )
            next(done)
            return []
        logger.info(
            "[%d/%d] done (%d/%d complete): %s",
            i, len(queries), next(done), len(queries), query,
        )
        return parse_search_items(items, query)

    logger.info("fetching %d queries, up to %d at a time", len(queries), workers)
    with ThreadPoolExecutor(max_workers=workers) as pool:
        per_query = await asyncio.gather(
            *(_search(i, q, pool) for i, q in enumerate(queries, start=1))
        )
    hits: list[ApifyHit] = [hit for q_hits in per_query for hit in q_hits]

    fresh = build_outputs(hits)  # deduped within this scrape
    existing = await service.load_pool()
    merged, to_persist, new_count = _merge_into_pool(existing, fresh)
    for video in to_persist:
        await service.save_video(video)  # upsert; no wipe
    with_tx = sum(1 for v in merged if v.transcript)
    await service.append_cost(
        CostEntry(
            execution_type=ExecutionType.SEARCH,
            at=datetime.now(timezone.utc),
            breakdown={"apify_usd": round(len(fresh) * APIFY_USD_PER_VIDEO, 4)},
            note=(
                f"{new_count} new of {len(fresh)} scraped from {len(queries)} "
                f"queries; pool now {len(merged)}"
            ),
        )
    )
    logger.info(
        "scraped %d videos (%d new); pool now %d (%d with a transcript)",
        len(fresh), new_count, len(merged), with_tx,
    )


async def classify_pool(service: VideosService, *, model: str) -> None:
    """Stage 2 (independently callable): READ the whole pool from disk, find the
    videos that aren't classified yet, tag them with genre + disciplines, and
    rewrite each tagged per-video file. Appends a TAG cost entry.

    Decoupled from scrape: it takes no list of "videos to check" — it simply scans
    every ``videos/*.yaml`` and tags whichever are still untagged. Incremental, so
    already-tagged videos are skipped (no re-spend on re-runs) and only new (or
    previously-failed) videos hit the LLM. The transcript is the quality signal: a
    video without one stays untagged (no gym_type) and never reaches the LLM, so it
    is a candidate for no gym."""
    llm = LiteLLMClient()
    classifier = VideoClassifier(llm=llm)
    videos = await service.load_pool()
    to_tag = [v for v in videos if not _is_tagged(v) and _has_transcript(v)]
    already = sum(1 for v in videos if _is_tagged(v))
    no_tx = sum(1 for v in videos if not _is_tagged(v) and not _has_transcript(v))
    total = len(to_tag)
    if total == 0:
        logger.info(
            "nothing to tag — %d already-tagged, %d without a transcript",
            already, no_tx,
        )
        return
    logger.info(
        "tagging %d untagged pooled videos with %s (concurrency %d); skipping %d "
        "already-tagged and %d without a transcript",
        total,
        model,
        CONCURRENCY,
        already,
        no_tx,
    )
    sem = asyncio.Semaphore(CONCURRENCY)
    counter = itertools.count(1)
    started = time.monotonic()
    results = await asyncio.gather(
        *(
            _tag_one(classifier, v, model, sem, total, counter, started)
            for v in to_tag
        )
    )
    elapsed = time.monotonic() - started

    failures = sum(1 for _, failed in results if failed)
    for video, _ in results:
        await service.save_video(video)
    await service.append_cost(
        CostEntry(
            execution_type=ExecutionType.TAG,
            at=datetime.now(timezone.utc),
            breakdown={"llm_usd": llm.cost},
            note=f"{total} videos tagged ({failures} failures); {already} skipped",
        )
    )
    logger.info(
        "tagged %d videos (%d failures); skipped %d already-tagged, %d without a "
        "transcript; %.1fs; est. cost ~$%.4f; wrote videos/",
        total,
        failures,
        already,
        no_tx,
        elapsed,
        llm.cost,
    )


async def run(
    *,
    root: Path,
    gym_id: str | None,
    lang: str,
    max_results: int,
    model: str,
    fetch_concurrency: int = FETCH_CONCURRENCY,
    queries: list[str] | None = None,
) -> None:
    """Scrape the gyms' queries into the pool, then classify the pool's untagged
    videos. The two stages are independent — scrape only writes the pool, and
    classify re-reads the pool from disk to find what still needs tagging; nothing
    is passed between them. ``queries`` (if given) overrides the gyms' queries —
    used to retry an explicit list (e.g. queries an Apify limit dropped)."""
    service = VideosService(root=root)
    await scrape_pool(
        service,
        gym_id=gym_id,
        lang=lang,
        max_results=max_results,
        fetch_concurrency=fetch_concurrency,
        queries=queries,
    )
    await classify_pool(service, model=model)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=_DEFAULT_ROOT)
    parser.add_argument(
        "--gym-id", default=None, help="only scrape this gym's queries (default: all)"
    )
    parser.add_argument("--lang", default=DEFAULT_LANG)
    parser.add_argument("--max-results", type=int, default=DEFAULT_MAX_RESULTS)
    parser.add_argument(
        "--fetch-concurrency",
        type=int,
        default=FETCH_CONCURRENCY,
        help=f"Apify runs fired at once during fetch (default {FETCH_CONCURRENCY}; "
        "the cap is memory: actor-pool-MB / 1024)",
    )
    parser.add_argument(
        "--queries-file",
        type=Path,
        default=None,
        help="scrape exactly these queries (one per line) instead of the gyms' "
        "queries — e.g. to retry queries an Apify limit dropped",
    )
    parser.add_argument("--model", default=VIDEO_CLASSIFY_MODEL)
    args = parser.parse_args(argv)

    explicit_queries: list[str] | None = None
    if args.queries_file is not None:
        explicit_queries = [
            line.strip()
            for line in args.queries_file.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]

    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    try:
        asyncio.run(
            run(
                root=args.root,
                gym_id=args.gym_id,
                lang=args.lang,
                max_results=args.max_results,
                model=args.model,
                fetch_concurrency=args.fetch_concurrency,
                queries=explicit_queries,
            )
        )
    except (ProviderError, SchemaValidationError) as exc:
        logger.error("%s", exc)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
