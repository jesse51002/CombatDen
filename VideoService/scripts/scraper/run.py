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
import itertools
import logging
import sys
import time
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
# Max videos tagged at once. Flash-Lite's rate limits comfortably allow this.
CONCURRENCY = 16


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
    service: VideosService, *, gym_id: str | None, lang: str, max_results: int
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
    queries = await _queries(service, gym_id)
    if not queries:
        logger.warning(
            "no gym queries%s — add videos.queries to gyms first; nothing to scrape",
            f" for gym {gym_id!r}" if gym_id else "",
        )
        return
    client = ApifyYouTubeSearchClient(apify_search_settings().apify_token)
    hits: list[ApifyHit] = []
    for i, query in enumerate(queries, start=1):
        logger.info("[%d/%d] searching: %s", i, len(queries), query)
        items = client.search(query, max_results=max_results, language=lang)
        hits.extend(parse_search_items(items, query))

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
    *, root: Path, gym_id: str | None, lang: str, max_results: int, model: str
) -> None:
    """Scrape the gyms' queries into the pool, then classify the pool's untagged
    videos. The two stages are independent — scrape only writes the pool, and
    classify re-reads the pool from disk to find what still needs tagging; nothing
    is passed between them."""
    service = VideosService(root=root)
    await scrape_pool(service, gym_id=gym_id, lang=lang, max_results=max_results)
    await classify_pool(service, model=model)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=_DEFAULT_ROOT)
    parser.add_argument(
        "--gym-id", default=None, help="only scrape this gym's queries (default: all)"
    )
    parser.add_argument("--lang", default=DEFAULT_LANG)
    parser.add_argument("--max-results", type=int, default=DEFAULT_MAX_RESULTS)
    parser.add_argument("--model", default=VIDEO_CLASSIFY_MODEL)
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    try:
        asyncio.run(
            run(
                root=args.root,
                gym_id=args.gym_id,
                lang=args.lang,
                max_results=args.max_results,
                model=args.model,
            )
        )
    except (ProviderError, SchemaValidationError) as exc:
        logger.error("%s", exc)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
