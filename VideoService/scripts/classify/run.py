"""Classify a company's fetched videos and rewrite videos_output.yaml.

    poetry run python -m scripts.classify.run --app-id muay_thai

Reads ``apps/<app_id>/videos_output.yaml`` (the batch result) and the company
brief, runs one Gemma call per video (genre + keep/drop verdict from the video's
real content, judged against the brief), and writes the tagged output back.

This is a separate pass from ``scripts.youtube_batch.run`` on purpose: it never
re-queries YouTube, so you can re-classify (or swap models) cheaply without
spending YouTube quota. Reads ``GEMINI_API_KEY`` from env / `.env`.

Classifies up to ``CONCURRENCY`` videos at once, logging a ``[done/total]``
progress counter as each completes. A single video that fails to classify (after
the client's built-in retries, or on a provider error) is non-fatal: it is marked
``is_good=False`` with no tag, and the run continues. One blocked video never
aborts the pass.
"""

from __future__ import annotations

import argparse
import asyncio
import itertools
import logging
import sys
import time
from datetime import datetime
from pathlib import Path

import yaml

from schema.video_classification import VideoClassification
from schema.video_output import VideoOutput
from schema.videos_config import VideosConfig
from src.api.service.videos_service import VideosService
from src.classification.video_classifier import (
    VIDEO_CLASSIFY_MODEL,
    VideoClassifier,
    format_duration,
)
from src.core.errors import ProviderError, SchemaValidationError
from src.shared.services.llm_client import LiteLLMClient

logger = logging.getLogger(__name__)

# scripts/classify/run.py -> <root>/apps
_DEFAULT_APPS_ROOT = Path(__file__).resolve().parent.parent.parent / "apps"
DEFAULT_OUTPUT_FILENAME = "videos_output.yaml"
# Max videos classified at once. Flash-Lite's rate limits comfortably allow
# this; raise with care + 429 backoff if you push much higher.
CONCURRENCY = 8


def _apply(video: VideoOutput, verdict: VideoClassification) -> VideoOutput:
    """A copy of ``video`` carrying the model's verdict."""
    return video.model_copy(update={"tag": verdict.tag, "is_good": verdict.is_good})


def _failed(video: VideoOutput) -> VideoOutput:
    """A copy of ``video`` marked not-good after a classification failure —
    kept (not dropped) so the failure is visible, with no genre."""
    return video.model_copy(update={"tag": None, "is_good": False})


async def _classify_one(
    classifier: VideoClassifier,
    video: VideoOutput,
    brief: VideosConfig,
    model: str,
    sem: asyncio.Semaphore,
    total: int,
    counter: "itertools.count[int]",
    started: float,
) -> tuple[VideoOutput, bool]:
    """Classify one video under the concurrency gate. Returns (video, failed?).
    The ``[done/total]`` counter advances as each call *completes* (so it tracks
    real progress under concurrency, not submission order). Each line shows the
    individual request time and the running average (wall time since ``started``
    over the number done). A miss after the client's retries — or a provider
    error — is caught and the video marked not-good rather than aborting the pass."""
    async with sem:
        t0 = time.monotonic()
        try:
            verdict = await classifier.classify(video, brief, model=model)
            now = time.monotonic()
            done = next(counter)
            logger.info(
                "[%d/%d] %s\n    length:  %s\n    tag:     %s\n    is_good: %s\n"
                "    req: %.1fs · avg: %.1fs ×%d workers\n",
                done,
                total,
                video.title,
                format_duration(video.duration_seconds),
                verdict.tag.value,
                verdict.is_good,
                now - t0,
                (now - started) / done,
                CONCURRENCY,
            )
            return _apply(video, verdict), False
        except (SchemaValidationError, ProviderError) as exc:
            now = time.monotonic()
            done = next(counter)
            logger.warning(
                "[%d/%d] %s\n    length:  %s\n"
                "    classify FAILED (req: %.1fs · avg: %.1fs ×%d workers): %s\n",
                done,
                total,
                video.title,
                format_duration(video.duration_seconds),
                now - t0,
                (now - started) / done,
                CONCURRENCY,
                exc,
            )
            return _failed(video), True


async def run(
    app_id: str,
    *,
    apps_root: Path,
    out_filename: str,
    model: str,
) -> Path:
    """Classify the company's fetched videos and write the output. Returns path."""
    service = VideosService(apps_root=apps_root)
    brief = await service.load(app_id)
    output = await service.load_output(app_id)

    llm = LiteLLMClient()
    classifier = VideoClassifier(llm=llm)
    total = len(output.videos)
    logger.info(
        "classifying %d videos with %s (concurrency %d)", total, model, CONCURRENCY
    )

    # Up to CONCURRENCY videos in flight at once; gather preserves input order in
    # the results, while the [done/total] counter advances on completion.
    sem = asyncio.Semaphore(CONCURRENCY)
    counter = itertools.count(1)
    started = time.monotonic()
    results = await asyncio.gather(
        *(
            _classify_one(
                classifier, video, brief, model, sem, total, counter, started
            )
            for video in output.videos
        )
    )
    elapsed = time.monotonic() - started

    classified = [video for video, _ in results]
    failures = sum(1 for _, failed in results if failed)
    kept = sum(1 for v in classified if v.is_good)
    classified_output = output.model_copy(
        update={
            "generated_at": datetime.now(output.generated_at.tzinfo),
            "videos": classified,
        }
    )
    out_path = apps_root / app_id / out_filename
    out_path.write_text(
        yaml.safe_dump(
            classified_output.model_dump(mode="json"),
            sort_keys=False,
            allow_unicode=True,
            default_flow_style=False,
        ),
        encoding="utf-8",
    )
    logger.info(
        "classified %d videos -> %d good, %d not-good, %d failures "
        "in %.1fs (%.2fs/video avg); est. cost ~$%.4f; wrote %s",
        total,
        kept,
        total - kept,
        failures,
        elapsed,
        elapsed / total if total else 0.0,
        llm.cost,
        out_path,
    )
    return out_path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app-id", required=True, help="company id under apps/")
    parser.add_argument("--apps-root", type=Path, default=_DEFAULT_APPS_ROOT)
    parser.add_argument("--out", default=DEFAULT_OUTPUT_FILENAME)
    parser.add_argument("--model", default=VIDEO_CLASSIFY_MODEL)
    args = parser.parse_args(argv)

    # Everything at WARNING (quiets litellm's per-call INFO + other library
    # chatter); our own pass logger at DEBUG so its [done/total] progress and
    # per-video verdict logging show. Bump the logger object directly (under
    # `python -m` this module's __name__ is "__main__", so a name-based lookup
    # would miss it).
    logging.basicConfig(level=logging.WARNING, format="%(levelname)s %(message)s")
    logger.setLevel(logging.DEBUG)
    try:
        asyncio.run(
            run(
                args.app_id,
                apps_root=args.apps_root,
                out_filename=args.out,
                model=args.model,
            )
        )
    except (ProviderError, SchemaValidationError) as exc:
        # Per-video failures are handled inline; this catches a setup-level
        # failure (e.g. no GEMINI_API_KEY) so it surfaces cleanly.
        logger.error("%s", exc)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
