"""Creator-avatar resolution — the scrape step's third YouTube call.

A video's ``search.list`` / ``videos.list`` snippet carries the CHANNEL id but no
creator avatar, so the avatar is resolved separately: ``channels.list`` batched
≤50 ids per call, **1 quota unit per call regardless of batch size**. A scrape
surfaces ~600 distinct channels, so covering all of them costs ~12 units against
the ~2,500 the same run already spends on ``search.list`` — a rounding error, and
hard-capped by ``worker_avatar_max_batches`` so it can never eat the quota.

**The avatar is a per-CHANNEL property stored per VIDEO.** ``video`` is a flat
pool row, so one channel's avatar is duplicated across every video it owns (~2 on
average). Every write therefore fans out by ``channel_url``, not by video id —
otherwise a refresh would fix only the rows a scrape happened to re-fetch and
leave the rest of the channel stale.

**Staleness is why this pass refreshes, not just fills.** A ``yt3.ggpht.com`` URL
is content-addressed: when a creator changes their picture the old URL eventually
404s, and a dead URL renders worse than no avatar at all. So the pass re-resolves
every channel the scrape touched, not only the ones missing an avatar — and since
every gym re-scrapes at least weekly (the tier-3 refresh floor), a channel that
still surfaces in any gym's queries is refreshed at least weekly for ~0 cost. When
the per-run cap binds, channels with NO avatar are resolved first: new coverage
always beats a refresh.

Failure posture matches the scrape's: one bad ``channels.list`` batch is logged
and dropped, never raised. An unresolved avatar simply stays as it was, and the
member UI omits an empty avatar entirely.
"""

from __future__ import annotations

import logging
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path

from schema.video_output import VideoOutput
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql
from src.worker.worker_config import settings
from src.worker.worker_transforms import (
    CHANNEL_URL,
    channel_id_from_url,
    parse_channel_avatars,
)
from src.worker.worker_youtube import MAX_PAGE_SIZE, WorkerYouTubeClient

logger = logging.getLogger(__name__)

SQL_DIR = Path(__file__).resolve().parent / "sql"
# channels.list costs 1 quota unit per CALL (≤50 ids), not per id.
QUOTA_UNITS_PER_CHANNELS_CALL = 1


@dataclass(frozen=True)
class AvatarResult:
    """What one avatar pass did: how much of the scrape's creator set it covered
    and what that cost in quota."""

    channels_seen: int  # distinct channels in this scrape's results
    channels_requested: int  # of those, how many the per-run cap let us ask about
    channels_resolved: int  # of those, how many came back with a usable avatar
    quota_units: int  # 1 per channels.list call


class WorkerAvatarResolver:
    """Resolves creator avatars from ``channels.list`` and fans each one out
    across every pool row of that channel."""

    def __init__(
        self, db_pool: DirectDatabasePool, youtube_client: WorkerYouTubeClient
    ) -> None:
        self._db = db_pool
        self._youtube = youtube_client

    async def refresh_for_scrape(
        self, videos: Sequence[VideoOutput]
    ) -> AvatarResult:
        """The scrape step's avatar pass: resolve + store the avatars of every
        channel this scrape surfaced, newest-uncovered first, under the per-run
        call cap. Runs AFTER the pool merge so the freshly-inserted rows are
        already there to be written."""
        ids_by_url = self._channels(videos)
        if not ids_by_url:
            return AvatarResult(0, 0, 0, 0)
        ordered = await self._order_uncovered_first(list(ids_by_url))
        cap = settings.worker_avatar_max_batches * MAX_PAGE_SIZE
        selected = ordered[:cap]
        if len(ordered) > cap:
            logger.warning(
                "avatar pass capped: %d of %d channels this run (cap %d batches)",
                cap,
                len(ordered),
                settings.worker_avatar_max_batches,
            )
        avatars, quota_units = await self.resolve(
            [ids_by_url[url] for url in selected]
        )
        await self.store(avatars)
        logger.info(
            "avatar pass: %d channels seen, %d requested, %d resolved (%d quota units)",
            len(ids_by_url),
            len(selected),
            len(avatars),
            quota_units,
        )
        return AvatarResult(
            channels_seen=len(ids_by_url),
            channels_requested=len(selected),
            channels_resolved=len(avatars),
            quota_units=quota_units,
        )

    async def resolve(
        self, channel_ids: Sequence[str]
    ) -> tuple[dict[str, str], int]:
        """``channels.list`` the given ids in ≤50-id batches → ``{channel_id:
        avatar_url}`` plus the quota units spent (1 per batch).

        Chunked HERE rather than inside the client so a failing batch costs only
        that batch: it is logged and dropped, the remaining batches still run, and
        the caller gets whatever resolved. Nothing raises — an unresolved channel
        keeps whatever avatar it already had."""
        avatars: dict[str, str] = {}
        quota_units = 0
        for start in range(0, len(channel_ids), MAX_PAGE_SIZE):
            batch = list(channel_ids[start : start + MAX_PAGE_SIZE])
            quota_units += QUOTA_UNITS_PER_CHANNELS_CALL
            try:
                items = await self._youtube.list_channels(batch)
            except Exception as exc:  # noqa: BLE001 - a bad batch never aborts a run
                logger.warning(
                    "channels.list failed for %d channel(s) (dropped): %s",
                    len(batch),
                    exc,
                )
                continue
            avatars.update(parse_channel_avatars(items))
        return avatars, quota_units

    async def store(self, avatars: Mapping[str, str]) -> int:
        """Write each resolved avatar (keyed by CHANNEL ID) onto every pool row of
        its channel. Returns the number of channels written."""
        return await self.store_by_url(
            {
                CHANNEL_URL.format(channel_id=channel_id): avatar
                for channel_id, avatar in avatars.items()
                if avatar
            }
        )

    async def store_by_url(self, avatars_by_url: Mapping[str, str]) -> int:
        """The single avatar write path, keyed by the stored ``channel_url``.

        Returns the number of channels written; the number of ROWS touched is
        deliberately unbounded — the avatar belongs to the channel, not the video,
        so it fans out across every row of that channel. The one-time backfill
        reuses this so there is exactly one place that writes an avatar."""
        rows = [
            {"channel_url": url, "channel_avatar_url": avatar}
            for url, avatar in avatars_by_url.items()
            if avatar
        ]
        if not rows:
            return 0
        await self._db.execute_with_retry(
            load_sql(SQL_DIR / "worker_update_channel_avatar.sql"), rows
        )
        return len(rows)

    @staticmethod
    def _channels(videos: Sequence[VideoOutput]) -> dict[str, str]:
        """``{channel_url: channel_id}`` for the scrape's videos, insertion-ordered
        and deduped. A video whose channel id could not be read (no ``channelId``
        in the snippet → empty ``channel_url``) is skipped."""
        ids_by_url: dict[str, str] = {}
        for video in videos:
            channel_id = channel_id_from_url(video.channel_url)
            if channel_id:
                ids_by_url.setdefault(video.channel_url, channel_id)
        return ids_by_url

    async def _order_uncovered_first(self, channel_urls: list[str]) -> list[str]:
        """Channels with NO stored avatar first, then the rest (a refresh). Only
        matters when the per-run cap binds — filling a gap always beats refreshing
        a value that is probably still good."""
        state = await self._db.fetch_all(
            load_sql(SQL_DIR / "worker_channel_avatar_state.sql"),
            {"channel_urls": channel_urls},
        )
        covered = {row["channel_url"] for row in state if row["has_avatar"]}
        return [url for url in channel_urls if url not in covered] + [
            url for url in channel_urls if url in covered
        ]
