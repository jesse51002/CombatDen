"""Scan the shared pool for one gym (or all) and write its good/rejected feed.

    poetry run python -m scripts.scan.run --gym-id vinyasa
    poetry run python -m scripts.scan.run --all-gyms

For each gym, the candidate set is the pooled videos whose ``gym_type`` includes
one of the gym's disciplines — so a gym only pays to scan its own slice, never the
whole pool. Each candidate gets one LLM call judging ``is_good`` against the gym's
``videos.specification``; the gym's ``good_video_ids`` / ``rejected_video_ids`` are
**overwritten** from the result (a scan is a fresh verdict, not an append), and a
``ScanCost`` is appended to the gym's ``scan_costs`` history. The pool itself is
never modified — approval is a per-gym verdict.

A separate pass from the scrape + classify (``scripts.scraper.run``). Reads the
tagging model key (e.g. ``GEMINI_API_KEY``) from env / `.env`. Scans up to
``CONCURRENCY`` candidates at once per gym; gyms are scanned sequentially. A single
failed scan is non-fatal: that video is treated as rejected and the run continues.
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
from schema.gym import Gym, ScanCost
from schema.video_output import VideoOutput
from src.api.service.videos_service import VideosService
from src.classification.gym_scanner import GymScanner
from src.classification.video_classifier import VIDEO_CLASSIFY_MODEL, format_duration
from src.core.errors import ProviderError, SchemaValidationError
from src.shared.interfaces.llm_client import LLMClient
from src.shared.services.llm_client import LiteLLMClient
from src.shared.util.video_id import video_id_from_url

logger = logging.getLogger(__name__)

# scripts/scan/run.py -> <root> (the single-tenant data root, holds gyms/ etc.)
_DEFAULT_ROOT = Path(__file__).resolve().parent.parent.parent
# 8, matching the tagger: 16 trips Gemini Flash-Lite's rate limit on a big
# fan-out, and here a failed call is treated as REJECTED (a false drop), so
# staying under the limit matters more (LLM_NUM_RETRIES rides out the rest).
CONCURRENCY = 8


def _candidates(gym: Gym, videos: list[VideoOutput]) -> list[VideoOutput]:
    """Pool videos whose disciplines intersect this gym's — the only slice the
    gym pays to scan. Untagged videos (empty gym_type) are candidates for no
    gym."""
    wanted = set(gym.gym_type)
    return [v for v in videos if wanted.intersection(v.gym_type)]


async def _scan_one(
    scanner: GymScanner,
    video: VideoOutput,
    gym: Gym,
    model: str,
    sem: asyncio.Semaphore,
    total: int,
    counter: "itertools.count[int]",
    started: float,
) -> tuple[str, bool]:
    """Scan one candidate. Returns (video_id, is_good). A failure is treated as
    rejected (is_good=False) so one blocked video never aborts the gym."""
    video_id = video_id_from_url(video.url)
    async with sem:
        t0 = time.monotonic()
        try:
            verdict = await scanner.scan(video, gym, model=model)
            now = time.monotonic()
            done = next(counter)
            logger.info(
                "[%d/%d] %s\n    length:  %s\n    is_good: %s\n"
                "    req: %.1fs · avg: %.1fs ×%d workers\n",
                done,
                total,
                video.title,
                format_duration(video.duration_seconds),
                verdict.is_good,
                now - t0,
                (now - started) / done,
                CONCURRENCY,
            )
            return video_id, verdict.is_good
        except (SchemaValidationError, ProviderError) as exc:
            done = next(counter)
            logger.warning(
                "[%d/%d] %s\n    scan FAILED (treated as rejected): %s\n",
                done,
                total,
                video.title,
                exc,
            )
            return video_id, False


async def _scan_gym(
    service: VideosService,
    gym: Gym,
    videos: list[VideoOutput],
    scanner: GymScanner,
    llm: LLMClient,
    model: str,
) -> None:
    """Scan one gym's candidate slice, OVERWRITE its good/rejected lists, and
    append this scan's LLM cost to the gym's ``scan_costs`` history."""
    candidates = _candidates(gym, videos)
    total = len(candidates)
    logger.info(
        "gym %s (%s): scanning %d candidates from the pool",
        gym.gym_id,
        ", ".join(g.value for g in gym.gym_type),
        total,
    )
    cost_before = llm.cost
    sem = asyncio.Semaphore(CONCURRENCY)
    counter = itertools.count(1)
    started = time.monotonic()
    results = await asyncio.gather(
        *(
            _scan_one(scanner, v, gym, model, sem, total, counter, started)
            for v in candidates
        )
    )
    good = [vid for vid, is_good in results if is_good]
    rejected = [vid for vid, is_good in results if not is_good]
    scan_cost = ScanCost(at=datetime.now(timezone.utc), usd=llm.cost - cost_before)
    updated_videos = gym.videos.model_copy(
        update={
            "good_video_ids": good,
            "rejected_video_ids": rejected,
            "scan_costs": [*gym.videos.scan_costs, scan_cost],
        }
    )
    await service.save_gym(gym.model_copy(update={"videos": updated_videos}))
    logger.info(
        "gym %s: %d good, %d rejected (of %d candidates); scan cost ~$%.4f",
        gym.gym_id,
        len(good),
        len(rejected),
        total,
        scan_cost.usd,
    )


async def run(*, root: Path, model: str, gym_id: str | None, all_gyms: bool) -> None:
    """Scan one gym (``gym_id``) or every gym (``all_gyms``) against the pool."""
    service = VideosService(root=root)
    videos = await service.load_pool()

    if all_gyms:
        gym_ids = await service.list_gyms()
    elif gym_id is not None:
        gym_ids = [gym_id]
    else:
        raise SystemExit("pass --gym-id <id> or --all-gyms")

    llm = LiteLLMClient()
    scanner = GymScanner(llm=llm)
    for gid in gym_ids:
        gym = await service.load_gym(gid)
        await _scan_gym(service, gym, videos, scanner, llm, model)
    # One ledger entry for the whole scan run (per-gym deltas live on each gym).
    await service.append_cost(
        CostEntry(
            execution_type=ExecutionType.SCAN,
            at=datetime.now(timezone.utc),
            breakdown={"llm_usd": llm.cost},
            note=f"{len(gym_ids)} gym(s) scanned",
        )
    )
    logger.info("scanned %d gym(s); est. cost ~$%.4f", len(gym_ids), llm.cost)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=_DEFAULT_ROOT)
    parser.add_argument("--model", default=VIDEO_CLASSIFY_MODEL)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--gym-id", help="scan just this gym")
    group.add_argument("--all-gyms", action="store_true", help="scan every gym")
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.WARNING, format="%(levelname)s %(message)s")
    logger.setLevel(logging.DEBUG)
    try:
        asyncio.run(
            run(
                root=args.root,
                model=args.model,
                gym_id=args.gym_id,
                all_gyms=args.all_gyms,
            )
        )
    except (ProviderError, SchemaValidationError) as exc:
        logger.error("%s", exc)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
