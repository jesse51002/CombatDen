"""Validate a gym file (or all of them) against the ``Gym`` model.

    poetry run python -m scripts.gym_maker.run check --gym-id vinyasa
    poetry run python -m scripts.gym_maker.run check --all

The ``videoservice`` skill (its ``gym_maker.md`` guide) authors a
``gyms/<gym_id>.yaml`` by hand, then runs this to confirm the file round-trips:
the schema is valid, the enum (``gym_type``) values exist, and the ``gym_id``
inside the file matches its filename stem. A green check means the gym is ready
for the scraper + scan; a red one prints exactly what to fix. This is the only
job in the pipeline that authors gyms — it never scrapes or scans.

Loads each gym through the same ``VideosService`` the API uses, so "valid here"
== "serveable by the API".
"""

from __future__ import annotations

import argparse
import asyncio
import logging
import sys
from pathlib import Path

from src.api.errors import InvalidConfigError, NotFoundError
from src.api.service.videos_service import VideosService

logger = logging.getLogger(__name__)

# scripts/gym_maker/run.py -> <root> (the single-tenant data root, holds gyms/).
_DEFAULT_ROOT = Path(__file__).resolve().parent.parent.parent


async def _check_one(service: VideosService, gym_id: str) -> bool:
    """Validate one gym. Returns whether it is OK (logs the verdict either way)."""
    try:
        gym = await service.load_gym(gym_id)
    except NotFoundError:
        logger.error("✗ %s: no such gym file (gyms/%s.yaml)", gym_id, gym_id)
        return False
    except InvalidConfigError as exc:
        logger.error("✗ %s: %s", gym_id, exc)
        return False
    if gym.gym_id != gym_id:
        logger.error(
            "✗ %s: gym_id in the file is %r but the filename stem is %r — they must "
            "match (rename the file or fix gym_id)",
            gym_id, gym.gym_id, gym_id,
        )
        return False
    logger.info(
        "✓ %s: valid — %s · theme %s · %d queries · %d good / %d rejected · "
        "classes=%s rewards=%s",
        gym_id,
        ", ".join(g.value for g in gym.gym_type),
        gym.theme,
        len(gym.videos.queries),
        len(gym.videos.good_video_ids),
        len(gym.videos.rejected_video_ids),
        "yes" if gym.classes else "no",
        "yes" if gym.rewards else "no",
    )
    return True


async def run(*, root: Path, gym_id: str | None, all_gyms: bool) -> bool:
    """Validate one gym (``gym_id``) or every gym (``all_gyms``). Returns whether
    everything checked passed."""
    service = VideosService(root=root)
    gym_ids = await service.list_gyms() if all_gyms else [gym_id]  # type: ignore[list-item]
    if all_gyms and not gym_ids:
        logger.warning("no gyms found under %s/gyms/", root)
        return True
    results = [await _check_one(service, gid) for gid in gym_ids]
    ok = all(results)
    logger.info("%d/%d gym(s) valid", sum(results), len(results))
    return ok


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    check = sub.add_parser("check", help="validate a gym file against the Gym model")
    check.add_argument("--root", type=Path, default=_DEFAULT_ROOT)
    group = check.add_mutually_exclusive_group(required=True)
    group.add_argument("--gym-id", help="validate just this gym")
    group.add_argument("--all", action="store_true", help="validate every gym")
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format="%(message)s")
    ok = asyncio.run(run(root=args.root, gym_id=args.gym_id, all_gyms=args.all))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
