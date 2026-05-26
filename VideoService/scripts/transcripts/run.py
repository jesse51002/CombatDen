"""Fetch transcripts for a company's fetched videos and cache them per file.

    poetry run python -m scripts.transcripts.run --app-id combatden

Reads ``apps/<app_id>/`` (the batch result), fetches a transcript for each video
that doesn't have one yet via Apify, and rewrites just those per-video files with
the full transcript on the ``transcript`` field. Reads ``APIFY_TOKEN`` from env /
`.env`.

This is a separate pass from the YouTube fetch and the classify pass on purpose:
it costs money per transcript ($0.0005 each) and is slow (an async Apify run), so
run it on demand. It only fetches videos that lack a transcript, so a re-run is
cheap — it picks up where a previous run left off and never re-pays for what it
already has.
"""

from __future__ import annotations

import argparse
import asyncio
import logging
import sys
from pathlib import Path

from src.api.service.videos_service import VideosService
from src.shared.util.video_id import video_id_from_url
from scripts.transcripts.apify import USD_PER_TRANSCRIPT, fetch_transcripts
from scripts.transcripts.config import transcript_settings

logger = logging.getLogger(__name__)

# scripts/transcripts/run.py -> <root>/apps
_DEFAULT_APPS_ROOT = Path(__file__).resolve().parent.parent.parent / "apps"


def _needs_transcript(transcript: str | None) -> bool:
    return not (transcript and transcript.strip())


def run(app_id: str, *, apps_root: Path) -> None:
    """Fetch and cache transcripts for the videos that lack one."""
    service = VideosService(apps_root=apps_root)
    output = asyncio.run(service.load_output(app_id))

    pending = [v for v in output.videos if _needs_transcript(v.transcript)]
    if not pending:
        logger.info(
            "all %d videos already have a transcript; nothing to fetch",
            len(output.videos),
        )
        return

    urls = list(dict.fromkeys(v.url for v in pending))  # order-preserving unique
    logger.info("fetching transcripts for %d videos", len(urls))
    results = fetch_transcripts(transcript_settings().apify_token, urls)

    async def _save() -> int:
        saved = 0
        for video in pending:
            vid = video_id_from_url(video.url)
            text = results.transcripts.get(vid)
            if text:
                # Got one: store it and clear any prior error.
                await service.save_video(
                    app_id,
                    video.model_copy(update={"transcript": text, "transcript_error": None}),
                )
                saved += 1
            else:
                # No transcript: record WHY (provider code, or not_returned when
                # the actor gave back no item for this url at all).
                reason = results.errors.get(vid, "not_returned")
                await service.save_video(
                    app_id, video.model_copy(update={"transcript_error": reason})
                )
        return saved

    found = asyncio.run(_save())
    # Apify charges per transcript attempted (= the urls we submitted this run).
    # Accumulate onto any prior spend, since a re-run only fetches what's missing.
    run_cost = len(urls) * USD_PER_TRANSCRIPT
    total_cost = (output.transcript_cost_usd or 0.0) + run_cost
    asyncio.run(
        service.save_manifest(
            app_id, output.model_copy(update={"transcript_cost_usd": total_cost})
        )
    )
    logger.info(
        "transcripts: %d requested, %d found, %d missing; this run ~$%.4f, "
        "total ~$%.4f; wrote %s/videos/",
        len(urls),
        found,
        len(urls) - found,
        run_cost,
        total_cost,
        apps_root / app_id,
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app-id", required=True, help="company id under apps/")
    parser.add_argument("--apps-root", type=Path, default=_DEFAULT_APPS_ROOT)
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    run(args.app_id, apps_root=args.apps_root)
    return 0


if __name__ == "__main__":
    sys.exit(main())
