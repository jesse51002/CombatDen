"""One-time backfill: give every pooled creator a channel avatar, and upgrade the
legacy `@handle` channel URLs to the canonical id form on the way.

    poetry run python -m scripts.backfill_avatars.run

The pool predates the worker's avatar pass, so ~11.8k channels have an empty
``video.channel_avatar_url`` and most of them are addressed only by the legacy
``youtube.com/@handle`` URL, which carries no channel id — and ``channels.list``
(the only endpoint that returns an avatar) takes ids. Two passes fix both at once:

  PASS 1 — recover the channel id for each handle-form channel via
  ``videos.list?id=<one of its videos>`` → ``snippet.channelId`` (50 video ids per
  call, 1 quota unit), then rewrite that channel's rows to
  ``youtube.com/channel/UC…``. This permanently removes the legacy handle data and
  is what lets every later pass recover the id from the stored URL by regex —
  which is why the pool needs no ``channel_id`` column.

  PASS 2 — ``channels.list?id=`` for every id-form channel still missing an avatar
  (≤50 per call, 1 unit) and store it on every row of that channel. Reuses the
  worker's ``WorkerAvatarResolver`` outright, so the one-time backfill and the
  ongoing scrape pass share ONE ``channels.list`` implementation and ONE avatar
  write path.

Cost: ~231 + ~236 ≈ 467 quota units against a 10,000/day budget. $0 — the YouTube
Data API is free within quota. No re-scrape, no LLM call.

**Resumable and idempotent.** Both passes derive their targets from the current
table state (still handle-form / still missing an avatar), so a crashed or
rate-limited run is resumed simply by running it again, and a completed run is a
no-op. ``--limit`` caps the CHANNELS each pass touches, for a cheap smoke test
before the real run.

Targets the DB in ``ENV_FILE`` (default ``.env``; ``ENV_FILE=.env.prod`` for prod)
and needs ``YOUTUBE_API_KEY``.

Cooperates with the import guards in ``scripts/sql/upsert_video.sql``: those
prevent a re-import of the legacy YAML from DOWNGRADING an id-form URL back to a
handle or blanking a stored avatar, while still allowing an upgrade — so a later
``make sync-gyms`` cannot undo this backfill.
"""

from __future__ import annotations

import argparse
import asyncio
import logging
import math
import sys
from pathlib import Path

from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql
from src.worker.worker_avatars import WorkerAvatarResolver
from src.worker.worker_config import settings
from src.worker.worker_transforms import (
    CHANNEL_URL,
    channel_id_from_url,
    parse_video_channel_ids,
)
from src.worker.worker_youtube import MAX_PAGE_SIZE, WorkerYouTubeClient

from scripts.shared.db_target import build_write_pool

logger = logging.getLogger(__name__)

SQL_DIR = Path(__file__).resolve().parent / "sql"
# videos.list / channels.list cost 1 quota unit per CALL (≤50 ids), not per id.
QUOTA_UNITS_PER_LIST_CALL = 1
# How many of a channel's videos to try before giving up on recovering its id. A
# representative video may have been deleted or made private since the scrape, in
# which case the API returns no item for it; a second/third attempt is nearly free
# (those ids ride along in the same ≤50 batches) and rescues the channel.
MAX_REPRESENTATIVES = 3
# Consecutive failing API batches tolerated before a pass stops. One transient
# error must not end a 231-call run, but an exhausted daily quota fails EVERY
# subsequent call — stopping keeps the log readable, and the run is resumable.
MAX_CONSECUTIVE_ERRORS = 3


class _Totals:
    """What the run did, printed at the end."""

    def __init__(self) -> None:
        self.urls_upgraded = 0
        self.urls_unresolved = 0
        self.avatars_stored = 0
        self.avatars_copied = 0  # filled from a sibling row, no API call
        self.avatars_unresolved = 0
        self.quota_units = 0


class BackfillAvatarsRunner:
    """Runs the two passes against whichever DB the pool points at."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        youtube: WorkerYouTubeClient,
        avatars: WorkerAvatarResolver,
        limit: int | None = None,
    ) -> None:
        self._db = db_pool
        self._youtube = youtube
        self._avatars = avatars
        self._limit = limit

    async def run(self) -> _Totals:
        totals = _Totals()
        await self._recover_channel_ids(totals)
        await self._fill_avatars(totals)
        return totals

    # --- pass 1: handle-form URL → canonical id-form URL ---------------------

    async def _recover_channel_ids(self, totals: _Totals) -> None:
        """Resolve each legacy handle channel's real id and rewrite its rows."""
        rows = await self._db.fetch_all(
            load_sql(SQL_DIR / "select_handle_channels.sql")
        )
        targets = self._capped(rows, "pass 1 (channel ids)")
        if not targets:
            return
        # channel_url -> its representative video ids (best-effort, in order).
        reps = {
            row["channel_url"]: list(row["video_ids"])[:MAX_REPRESENTATIVES]
            for row in targets
        }
        resolved: dict[str, str] = {}
        for attempt in range(MAX_REPRESENTATIVES):
            pending = {
                url: ids[attempt]
                for url, ids in reps.items()
                if url not in resolved and len(ids) > attempt
            }
            if not pending:
                break
            logger.info(
                "pass 1 round %d: resolving %d channel(s) via videos.list",
                attempt + 1,
                len(pending),
            )
            by_video = await self._list_video_channel_ids(
                list(pending.values()), totals
            )
            for url, video_id in pending.items():
                channel_id = by_video.get(video_id)
                if channel_id:
                    resolved[url] = channel_id

        await self._write_upgraded_urls(resolved, totals)
        totals.urls_unresolved = len(reps) - len(resolved)
        if totals.urls_unresolved:
            logger.warning(
                "pass 1: %d channel(s) unresolved (every representative video is "
                "gone) — left on their legacy handle URL",
                totals.urls_unresolved,
            )

    async def _list_video_channel_ids(
        self, video_ids: list[str], totals: _Totals
    ) -> dict[str, str]:
        """``videos.list`` the ids in ≤50 batches → ``{video_id: channel_id}``.
        Chunked here (not in the client) so one failing batch costs only itself."""
        found: dict[str, str] = {}
        consecutive_errors = 0
        for start in range(0, len(video_ids), MAX_PAGE_SIZE):
            batch = video_ids[start : start + MAX_PAGE_SIZE]
            totals.quota_units += QUOTA_UNITS_PER_LIST_CALL
            try:
                items = await self._youtube.list_videos(batch)
            except Exception as exc:  # noqa: BLE001 - bounded, then stop the pass
                consecutive_errors += 1
                logger.warning(
                    "videos.list failed for %d id(s) (%d consecutive): %s",
                    len(batch),
                    consecutive_errors,
                    exc,
                )
                if consecutive_errors >= MAX_CONSECUTIVE_ERRORS:
                    logger.error(
                        "stopping pass 1 after %d consecutive failures — re-run to "
                        "resume where it left off",
                        consecutive_errors,
                    )
                    break
                continue
            consecutive_errors = 0
            found.update(parse_video_channel_ids(items))
        return found

    async def _write_upgraded_urls(
        self, resolved: dict[str, str], totals: _Totals
    ) -> None:
        """Rewrite each resolved channel's rows to the canonical id-form URL."""
        rows = [
            {
                "handle_url": handle_url,
                "id_form_url": CHANNEL_URL.format(channel_id=channel_id),
            }
            for handle_url, channel_id in resolved.items()
        ]
        if not rows:
            return
        await self._db.execute_with_retry(
            load_sql(SQL_DIR / "update_channel_url.sql"), rows
        )
        totals.urls_upgraded = len(rows)
        logger.info("pass 1: upgraded %d channel URL(s) to the id form", len(rows))

    # --- pass 2: fill the avatars -------------------------------------------

    async def _fill_avatars(self, totals: _Totals) -> None:
        """Store an avatar for every id-form channel still missing one."""
        rows = await self._db.fetch_all(
            load_sql(SQL_DIR / "select_avatar_targets.sql")
        )
        targets = self._capped(rows, "pass 2 (avatars)")
        if not targets:
            return
        # A channel some other row already knows the avatar for needs no API call.
        copyable = {
            row["channel_url"]: row["known_avatar"]
            for row in targets
            if row["known_avatar"]
        }
        if copyable:
            totals.avatars_copied = await self._avatars.store_by_url(copyable)
            logger.info(
                "pass 2: copied %d avatar(s) already known from a sibling row "
                "(no quota spent)",
                len(copyable),
            )

        ids_by_url = {
            row["channel_url"]: channel_id_from_url(row["channel_url"])
            for row in targets
            if row["channel_url"] not in copyable
        }
        ids_by_url = {url: cid for url, cid in ids_by_url.items() if cid}
        if not ids_by_url:
            return
        logger.info(
            "pass 2: resolving %d channel(s) via channels.list (~%d calls)",
            len(ids_by_url),
            math.ceil(len(ids_by_url) / MAX_PAGE_SIZE),
        )
        avatars, quota_units = await self._avatars.resolve(list(ids_by_url.values()))
        totals.quota_units += quota_units
        totals.avatars_stored = await self._avatars.store(avatars)
        totals.avatars_unresolved = len(ids_by_url) - len(avatars)
        logger.info(
            "pass 2: stored %d avatar(s), %d channel(s) returned none",
            totals.avatars_stored,
            totals.avatars_unresolved,
        )

    # --- helpers -------------------------------------------------------------

    def _capped(self, rows: list[dict], label: str) -> list[dict]:
        """Apply ``--limit`` (a CHANNEL cap, the unit of work in both passes)."""
        if not rows:
            logger.info("%s: nothing to do", label)
            return []
        if self._limit is not None and len(rows) > self._limit:
            logger.info(
                "%s: %d channel(s) to do — capped to %d by --limit",
                label,
                len(rows),
                self._limit,
            )
            return rows[: self._limit]
        logger.info("%s: %d channel(s) to do", label, len(rows))
        return rows


async def run(*, limit: int | None = None) -> _Totals:
    if not settings.youtube_api_key:
        raise SystemExit("no YOUTUBE_API_KEY configured — nothing can be resolved")
    pool = build_write_pool()
    youtube = WorkerYouTubeClient(settings.youtube_api_key)
    runner = BackfillAvatarsRunner(
        pool, youtube, WorkerAvatarResolver(pool, youtube), limit=limit
    )
    try:
        totals = await runner.run()
    finally:
        await pool.dispose()
    logger.info(
        "backfill-avatars done: %d channel URL(s) upgraded (%d unresolved), "
        "%d avatar(s) stored + %d copied (%d unresolved) — %d quota units, $0",
        totals.urls_upgraded,
        totals.urls_unresolved,
        totals.avatars_stored,
        totals.avatars_copied,
        totals.avatars_unresolved,
        totals.quota_units,
    )
    return totals


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Process at most N channels per pass — a cheap smoke test (a few "
        "quota units) proving both passes end-to-end before the real run.",
    )
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format="%(message)s")
    asyncio.run(run(limit=args.limit))
    return 0


if __name__ == "__main__":
    sys.exit(main())
