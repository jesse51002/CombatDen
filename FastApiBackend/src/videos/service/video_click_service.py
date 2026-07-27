"""VideoClickService — record a member opening a video from the FEED.

The rec surface (``VideoRecClickService``) only ever sees the ONE rotating
recommendation the system served. Every other open — the feed hero, a genre
carousel, a genre "view all" list, the profile's level-up carousel — goes
through here, so the member's taste profile learns from the videos the member
chose for themselves and not only from what we already recommended.

Two properties define this service:

* **Append-only. There is deliberately NO dedup and no idempotency key.** A
  repeat open of the same video is real signal (re-watching a drill means
  something), so each open logs its own ``member_activities`` row. This is the
  opposite of the rec click, which stamps ``member_video_recs.clicked_at`` and
  is therefore idempotent by construction. Do not "fix" this into a dedup.
* **It logs only videos the gym's feed actually serves.** The video id is
  caller-supplied, so it is checked against the shared served-feed predicate
  first; an unknown or foreign id is a ``VideoNotInFeedError`` (404 at the
  router), never a logged activity.

Both writers produce the SAME ``activity_info`` shape via the one shared insert
(``member_activity_video_click_insert.sql``) — ``video_id`` always, ``rec_id``
NULL here — so the taste-profile query (``member_profile_source.sql``, which
reads only ``activity_info->>'video_id'``) consumes them identically.
"""

from __future__ import annotations

from uuid import UUID

from schema.member_activity import MemberActivityType
from schema.video import GymVideoScanStatus
from sqlalchemy import text

from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql
from src.videos import SQL_DIR
from src.videos.schema.video_click_schema import MemberVideoClickResponse
from src.videos.service.member_video_profile_refresh_runner import (
    MemberVideoProfileRefreshRunner,
)


class VideoNotInFeedError(ValueError):
    """The video is not in this gym's served feed (→ 404)."""


class VideoClickService:
    """Log a feed video open, then fire a fire-and-forget profile refresh."""

    def __init__(
        self,
        *,
        db_pool: DirectDatabasePool,
        refresh_runner: MemberVideoProfileRefreshRunner,
    ) -> None:
        self._db = db_pool
        self._refresh = refresh_runner

    async def record_click(
        self, gym_id: UUID, member_id: UUID, video_id: str
    ) -> MemberVideoClickResponse:
        """Log ``member_id`` opening ``video_id`` from ``gym_id``'s feed.

        Every call logs a row — see the module docstring on why there is no
        dedup. A video the gym's feed does not serve raises
        ``VideoNotInFeedError``.
        """
        if not await self._is_served(gym_id, video_id):
            raise VideoNotInFeedError("Video not found in this gym's feed")

        await self._log_activity(gym_id, member_id, video_id)

        # Same trigger as the rec click, and it is NOT too hot to fire per tap:
        # the runner coalesces per member (a second fire while one is in flight
        # is dropped-but-marked-dirty) and ``refresh_if_due`` itself no-ops
        # inside ``video_profile_refresh_cooldown_days``. So a burst of feed
        # taps costs at most one paid summary+embedding build per cooldown
        # window — and a self-chosen open is exactly the signal the profile
        # should learn from. Failures never surface to the caller.
        self._refresh.start(member_id, gym_id)
        return MemberVideoClickResponse(video_id=video_id)

    async def _is_served(self, gym_id: UUID, video_id: str) -> bool:
        """Does the gym's SERVED feed contain this video id?"""
        candidate_source = load_sql(
            SQL_DIR / "videos_feed_candidate_source.sql"
        )
        sql = load_sql(
            SQL_DIR / "video_click_feed_check.sql",
            {"candidate_source": candidate_source},
        )
        params = {
            "gym_id": str(gym_id),
            "scan_status": GymVideoScanStatus.accepted.value,
            "video_id": video_id,
        }
        async with self._db.session() as session:
            row = (
                (await session.execute(text(sql), params)).mappings().fetchone()
            )
        return row is not None

    async def _log_activity(
        self, gym_id: UUID, member_id: UUID, video_id: str
    ) -> None:
        """Append one ``video_clicked`` activity — no dedup, by design."""
        sql = load_sql(SQL_DIR / "member_activity_video_click_insert.sql")
        params = {
            "member_id": str(member_id),
            "gym_id": str(gym_id),
            "activity_type": MemberActivityType.video_clicked.value,
            "video_id": video_id,
            # No rec served this open — the member picked it out of the feed.
            "rec_id": None,
        }
        async with self._db.session() as session, session.begin():
            await session.execute(text(sql), params)
