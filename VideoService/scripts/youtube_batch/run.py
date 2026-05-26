"""Run a company's videos_config.yaml against the YouTube Data API and write
videos_output.yaml.

    poetry run python -m scripts.youtube_batch.run --app-id combatden

Reads ``YOUTUBE_API_KEY`` from env / `.env`. One brief (10-20 queries) costs
~1,000-2,000 quota units of the 10,000/day free allowance, so don't re-run
casually — the output YAML is the cache.
"""

from __future__ import annotations

import argparse
import asyncio
import logging
import sys
from datetime import datetime, timezone
from pathlib import Path

from schema.video_output import VideosOutput
from scripts.youtube_batch.client import QuotaExceededError, YouTubeClient
from scripts.youtube_batch.config import batch_settings
from scripts.youtube_batch.transform import (
    SearchHit,
    VideoStats,
    build_outputs,
    parse_channel_avatars,
    parse_search_response,
    parse_video_stats,
)
from src.api.service.videos_service import VideosService

logger = logging.getLogger(__name__)

# scripts/youtube_batch/run.py -> <root>/apps
_DEFAULT_APPS_ROOT = Path(__file__).resolve().parent.parent.parent / "apps"
DEFAULT_MAX_RESULTS = 50
DEFAULT_LANG = "en"


def _unique(values: list[str]) -> list[str]:
    """Order-preserving de-dup; drops empties."""
    return [v for v in dict.fromkeys(values) if v]


def run(app_id: str, *, apps_root: Path, lang: str, max_results: int) -> None:
    """Execute the brief's searches and persist the feed (manifest + one file
    per video) via the store."""
    service = VideosService(apps_root=apps_root)
    config = asyncio.run(service.load(app_id))
    client = YouTubeClient(batch_settings().youtube_api_key)

    hits: list[SearchHit] = []
    for i, search in enumerate(config.searches, start=1):
        logger.info("[%d/%d] searching: %s", i, len(config.searches), search.query)
        response = client.search(search.query, max_results=max_results, lang=lang)
        hits.extend(parse_search_response(response, search.query))

    video_ids = _unique([hit.video_id for hit in hits])
    channel_ids = _unique([hit.channel_id for hit in hits])
    logger.info(
        "%d hits across %d searches -> %d unique videos, %d unique channels",
        len(hits), len(config.searches), len(video_ids), len(channel_ids),
    )

    stats: dict[str, VideoStats] = {}
    for response in client.fetch_video_stats(video_ids):
        stats.update(parse_video_stats(response))
    avatars: dict[str, str] = {}
    for response in client.fetch_channel_avatars(channel_ids):
        avatars.update(parse_channel_avatars(response))

    output = VideosOutput(
        company_name=config.company_name,
        app_id=app_id,
        generated_at=datetime.now(timezone.utc),
        queries=[search.query for search in config.searches],
        quota_units_estimate=client.quota_units,
        videos=build_outputs(hits, avatars, stats),
    )

    asyncio.run(service.save_output(app_id, output))
    logger.info(
        "wrote %d videos to %s/videos/ (~%d quota units)",
        len(output.videos), apps_root / app_id, output.quota_units_estimate,
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app-id", required=True, help="company id under apps/")
    parser.add_argument("--apps-root", type=Path, default=_DEFAULT_APPS_ROOT)
    parser.add_argument("--lang", default=DEFAULT_LANG)
    parser.add_argument("--max-results", type=int, default=DEFAULT_MAX_RESULTS)
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    try:
        run(
            args.app_id,
            apps_root=args.apps_root,
            lang=args.lang,
            max_results=args.max_results,
        )
    except QuotaExceededError as exc:
        logger.error("%s", exc)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
