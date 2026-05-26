"""Clear the classification verdict on a company's videos, keeping transcripts.

    poetry run python -m scripts.reset_classifications --app-id bjj   # one app
    poetry run python -m scripts.reset_classifications               # every app

Nulls ``tag`` / ``is_good`` / ``reason`` on every per-video file so the feed is
back to its freshly-fetched state and ``make classify`` can be re-run clean. The
expensive fields (transcript, stats, etc.) are left untouched. A dev/test helper
for iterating on the classifier — it spends nothing and touches no external API.
"""

from __future__ import annotations

import argparse
import asyncio
import logging
import sys
from pathlib import Path

from src.api.service.videos_service import VideosService

# scripts/reset_classifications.py -> <root>/apps
_DEFAULT_APPS_ROOT = Path(__file__).resolve().parent.parent / "apps"

logger = logging.getLogger(__name__)


async def _reset_app(service: VideosService, app_id: str) -> tuple[int, int]:
    """Null the verdict on every video of one app. Returns (changed, total)."""
    output = await service.load_output(app_id)
    changed = 0
    for video in output.videos:
        if video.tag is None and video.is_good is None and video.reason is None:
            continue
        await service.save_video(
            app_id, video.model_copy(update={"tag": None, "is_good": None, "reason": None})
        )
        changed += 1
    return changed, len(output.videos)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app-id", help="company id under apps/ (default: all apps)")
    parser.add_argument("--apps-root", type=Path, default=_DEFAULT_APPS_ROOT)
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    service = VideosService(apps_root=args.apps_root)
    if args.app_id:
        app_ids = [args.app_id]
    else:
        app_ids = [p.parent.name for p in sorted(args.apps_root.glob("*/videos_output.yaml"))]

    for app_id in app_ids:
        changed, total = asyncio.run(_reset_app(service, app_id))
        logger.info("%s: reset %d of %d videos (transcripts kept)", app_id, changed, total)
    return 0


if __name__ == "__main__":
    sys.exit(main())
