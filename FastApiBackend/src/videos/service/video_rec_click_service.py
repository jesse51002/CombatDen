"""VideoRecClickService — record a member opening (clicking) a recommendation.

On the FIRST click of a served rec it stamps ``member_video_recs.clicked_at``
(idempotent via ``clicked_at IS NULL``), logs a ``video_clicked`` member
activity carrying the video + rec ids, and fires a fire-and-forget profile
refresh (the click is fresh taste signal). A repeat click is idempotent — it
neither re-stamps, re-logs, nor re-fires. A rec that doesn't belong to this
member + gym is a ``RecNotFoundError`` (mapped to 404 by the router).
"""

from __future__ import annotations

from uuid import UUID

from schema.member_activity import MemberActivityType
from sqlalchemy import text

from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql
from src.videos import SQL_DIR
from src.videos.schema.video_recs_schema import VideoRecClickResponse
from src.videos.service.member_video_profile_refresh_runner import (
    MemberVideoProfileRefreshRunner,
)


class RecNotFoundError(ValueError):
    """The recommendation does not exist for this member + gym (→ 404)."""


class VideoRecClickService:
    """Stamp + log a rec click, then fire a fire-and-forget profile refresh."""

    def __init__(
        self,
        *,
        db_pool: DirectDatabasePool,
        refresh_runner: MemberVideoProfileRefreshRunner,
    ) -> None:
        self._db = db_pool
        self._refresh = refresh_runner

    async def record_click(
        self, gym_id: UUID, member_id: UUID, rec_id: UUID
    ) -> VideoRecClickResponse:
        """Record a click on ``rec_id`` for ``member_id`` at ``gym_id``.

        First click: stamps ``clicked_at``, logs the activity, fires the
        refresh. Repeat click: idempotent 200 (no re-stamp / re-log / re-fire).
        Unknown rec for this member + gym: ``RecNotFoundError``.
        """
        first_row = await self._stamp_first_click(gym_id, member_id, rec_id)
        if first_row is not None:
            self._refresh.start(member_id, gym_id)
            return VideoRecClickResponse(
                clicked=True, video_id=first_row["video_id"]
            )

        existing = await self._load_rec(gym_id, member_id, rec_id)
        if existing is None:
            raise RecNotFoundError("Recommendation not found for this member")
        return VideoRecClickResponse(
            clicked=False, video_id=existing["video_id"]
        )

    async def _stamp_first_click(
        self, gym_id: UUID, member_id: UUID, rec_id: UUID
    ) -> dict | None:
        """Stamp clicked_at + log the activity in one txn (None on repeat)."""
        update_sql = load_sql(SQL_DIR / "video_rec_click_update.sql")
        activity_sql = load_sql(SQL_DIR / "member_activity_video_click_insert.sql")
        scope = {
            "rec_id": str(rec_id),
            "member_id": str(member_id),
            "gym_id": str(gym_id),
        }
        async with self._db.session() as session, session.begin():
            row = (
                (await session.execute(text(update_sql), scope))
                .mappings()
                .fetchone()
            )
            if row is None:
                return None
            await session.execute(
                text(activity_sql),
                {
                    "member_id": str(member_id),
                    "gym_id": str(gym_id),
                    "activity_type": MemberActivityType.video_clicked.value,
                    "video_id": row["video_id"],
                    "rec_id": str(rec_id),
                },
            )
            return dict(row)

    async def _load_rec(
        self, gym_id: UUID, member_id: UUID, rec_id: UUID
    ) -> dict | None:
        """Look up a rec scoped to member + gym (None when it doesn't exist)."""
        sql = load_sql(SQL_DIR / "video_rec_load.sql")
        params = {
            "rec_id": str(rec_id),
            "member_id": str(member_id),
            "gym_id": str(gym_id),
        }
        async with self._db.session() as session:
            row = (
                (await session.execute(text(sql), params)).mappings().fetchone()
            )
        return dict(row) if row is not None else None
