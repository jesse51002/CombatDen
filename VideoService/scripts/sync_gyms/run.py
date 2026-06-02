"""Sync the hand-authored gym files into SQL.

    poetry run python -m scripts.sync_gyms.run --gym-id vinyasa
    poetry run python -m scripts.sync_gyms.run --all

The gym configs stay git-tracked YAML (`gyms/<gym_id>.yaml`) as the human source
of truth; this loads + validates each against the ``Gym`` model and upserts it
into ``video_gym`` + its query / class / reward child tables (replaced wholesale,
so the sync is idempotent). It does NOT touch a gym's curated feed
(``video_gym_feed``) or cost log — those are owned by the scan / import.

Requires ``DATABASE_URL`` in ``.env`` (the shared Supabase Postgres). Run after
the migration has created the ``video_*`` tables.
"""

from __future__ import annotations

import argparse
import asyncio
import logging
import sys
from pathlib import Path

from pydantic import ValidationError

from scripts.shared.db_target import build_write_pool
from scripts.shared.gym_yaml_store import list_gym_ids, load_gym_yaml
from scripts.shared.video_db_writer import VideoDbWriter

logger = logging.getLogger(__name__)

# scripts/sync_gyms/run.py -> <root> (holds gyms/).
_DEFAULT_ROOT = Path(__file__).resolve().parent.parent.parent


async def run(*, root: Path, gym_id: str | None, all_gyms: bool) -> bool:
    """Sync one gym (``gym_id``) or every gym (``all_gyms``) into SQL. Returns
    whether everything synced cleanly."""
    gym_ids = list_gym_ids(root) if all_gyms else [gym_id]  # type: ignore[list-item]
    if all_gyms and not gym_ids:
        logger.warning("no gyms found under %s/gyms/", root)
        return True

    pool = build_write_pool()
    writer = VideoDbWriter(pool)
    ok = True
    try:
        for gid in gym_ids:
            try:
                gym = load_gym_yaml(root, gid)
            except (FileNotFoundError, ValidationError, ValueError) as exc:
                logger.error("✗ %s: %s", gid, exc)
                ok = False
                continue
            if gym.gym_id != gid:
                logger.error(
                    "✗ %s: gym_id in the file is %r but the filename stem is %r",
                    gid, gym.gym_id, gid,
                )
                ok = False
                continue
            await writer.upsert_gym(gym)
            logger.info(
                "✓ %s synced — %s · theme %s · %d queries · classes=%s rewards=%s",
                gid,
                ", ".join(g.value for g in gym.gym_type),
                gym.theme,
                len(gym.videos.queries),
                "yes" if gym.classes else "no",
                "yes" if gym.rewards else "no",
            )
    finally:
        await pool.dispose()
    logger.info("%d gym(s) processed", len(gym_ids))
    return ok


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=_DEFAULT_ROOT)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--gym-id", help="sync just this gym")
    group.add_argument("--all", action="store_true", help="sync every gym")
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format="%(message)s")
    ok = asyncio.run(run(root=args.root, gym_id=args.gym_id, all_gyms=args.all))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
