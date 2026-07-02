"""Reverse ONE member's recorded check-in on a KNOWN occurrence.

The reusable core of a check-in reversal, scoped to a single member on one
occurrence — identified by ``(class_id, original_date, original_time)``, its
full identity key (a class may occur several times per day; the time picks
the exact slot): delete that member's attendance row, claw back the class's
``points_worth`` (floored at 0), drop one ``class_attended`` activity, and
reverse the auto-end on the charged trial / one_time pack when the delete
drops it back below capacity. Every step runs in the caller's OPEN
transaction (no commit here), so a bulk caller can reverse many members
atomically.

This unit does NOT resolve the occurrence beyond its identity key — the
caller passes the slot key and the class's ``points_worth`` (a bulk caller
loads those once and reuses them across the loop). It imports NOTHING from
``src.classes``: the single-member remover
(``CheckinRemover``), the whole-occurrence undo (``ClassesUndoService``), and
the schedule-version mint engine (``ClassesVersionsService``) — both of which
live in ``src.classes`` — all call this, and a ``src.classes`` import here
would create a Python import cycle.
"""

from datetime import date, time
from uuid import UUID

from dateutil.relativedelta import relativedelta
from schema.membership_plan import PlanType
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.checkin import SQL_DIR
from src.checkin.schema.checkin_schema import (
    CLASS_ATTENDED_ACTIVITY_TYPE,
    CheckinRemoveResponse,
)
from src.shared.sql_loader import load_sql


class CheckinReverser:
    """Reverses one member's check-in on a known occurrence.

    Stateless: every step takes the caller's ``AsyncSession`` and runs in that
    open transaction (no commit). Shared by ``CheckinRemover`` (one member),
    ``ClassesUndoService`` (every attendee, looped, on cancel / future
    reschedule), and ``ClassesVersionsService`` (every attendee, looped, on
    the version-change wipe) so the reversal — attendance delete + points
    claw-back + activity drop + pack auto-end reversal — has a single
    implementation.
    """

    async def reverse(
        self,
        session: AsyncSession,
        member_id: UUID,
        gym_id: UUID,
        class_id: UUID,
        original_date: date,
        original_time: time,
        points_worth: int,
    ) -> CheckinRemoveResponse:
        """Reverse ``member_id``'s check-in on the occurrence identified by
        ``(class_id, original_date, original_time)``.

        Deletes the member's attendance row, claws back ``points_worth`` (floored
        at 0 by the balance CHECK), drops one ``class_attended`` activity, and
        clears the auto-end on the charged trial / one_time pack when the delete
        drops it back below capacity — all in the caller's OPEN transaction (no
        commit).

        Returns a ``removed=False`` result (no error) when the member had no
        attendance on this occurrence.
        """
        deleted = await self._delete_attendance(
            session, member_id, class_id, original_date, original_time
        )
        if deleted is None:
            return CheckinRemoveResponse(removed=False)

        await self._revert_points(session, member_id, gym_id, points_worth)
        await self._delete_activity(session, member_id, gym_id, class_id)
        unended = await self._reverse_auto_end(
            session, member_id, deleted["item_id"]
        )

        return CheckinRemoveResponse(
            removed=True,
            points_reverted=points_worth,
            membership_unended=unended,
        )

    # -- steps -----------------------------------------------------------

    async def _delete_attendance(
        self,
        session: AsyncSession,
        member_id: UUID,
        class_id: UUID,
        original_date: date,
        original_time: time,
    ) -> dict | None:
        """Delete the member's attendance row; return its (item_id, plan_id)."""
        return await self._fetchone(
            session,
            load_sql(SQL_DIR / "checkin_delete_member_attendance.sql"),
            {
                "member_id": str(member_id),
                "class_id": str(class_id),
                "original_date": original_date,
                "original_time": original_time,
            },
        )

    async def _revert_points(
        self,
        session: AsyncSession,
        member_id: UUID,
        gym_id: UUID,
        points: int,
    ) -> None:
        """Claw back the awarded points, floored at 0 (the balance CHECK)."""
        await session.execute(
            text(load_sql(SQL_DIR / "checkin_revert_points.sql")),
            {"points": points, "m": str(member_id), "g": str(gym_id)},
        )

    async def _delete_activity(
        self,
        session: AsyncSession,
        member_id: UUID,
        gym_id: UUID,
        class_id: UUID,
    ) -> None:
        """Remove one matching class_attended loyalty-feed row (best effort)."""
        await session.execute(
            text(load_sql(SQL_DIR / "checkin_delete_attended_activity.sql")),
            {
                "m": str(member_id),
                "g": str(gym_id),
                "activity_type": CLASS_ATTENDED_ACTIVITY_TYPE,
                "class_id": str(class_id),
            },
        )

    async def _reverse_auto_end(
        self,
        session: AsyncSession,
        member_id: UUID,
        item_id: UUID | None,
    ) -> UUID | None:
        """Restore the pack's end_date if the removal drops it below
        capacity: back to the plan's duration-derived expiry (start_date +
        duration, mirroring the purchase stamp) or NULL for a pure
        class-count pack — never a blind NULL, which would erase a duration
        pack's natural expiry. None item_id (no-membership attendance)
        charged nothing, so there is nothing to reverse. Returns the item_id
        only when the end_date actually changed (a pack already sitting at
        its duration expiry is a no-op)."""
        if item_id is None:
            return None
        info = await self._fetchone(
            session,
            load_sql(SQL_DIR / "checkin_load_membership_for_reversal.sql"),
            {"item_id": str(item_id)},
        )
        if info is None or not self._is_depletion_auto_end(info):
            return None
        remaining = await self._count_attendance(session, item_id, member_id)
        capacity = int(info["class_count"]) * int(info["quantity"])
        if remaining >= capacity:
            return None
        changed = await self._fetchone(
            session,
            load_sql(SQL_DIR / "checkin_reverse_membership_end.sql"),
            {
                "item_id": str(item_id),
                "member_id": str(member_id),
                "end_date": self._duration_end_date(info),
            },
        )
        return item_id if changed is not None else None

    @staticmethod
    def _duration_end_date(info: dict) -> date | None:
        """The pack's duration-derived expiry (start_date + the plan's
        duration — the same derivation the purchase stamps), or None for a
        pure class-count pack with no duration."""
        amount, unit = info["duration_amount"], info["duration_unit"]
        if amount is None or unit is None:
            return None
        start: date = info["start_date"]
        if unit == "week":
            return start + relativedelta(weeks=amount)
        if unit == "month":
            return start + relativedelta(months=amount)
        if unit == "year":
            return start + relativedelta(years=amount)
        return None

    async def _count_attendance(
        self, session: AsyncSession, item_id: UUID, member_id: UUID
    ) -> int:
        """Attendance still recorded against the pack (post-delete)."""
        row = await self._fetchone(
            session,
            load_sql(SQL_DIR / "checkin_count_attendance.sql"),
            {"item_id": str(item_id), "member_id": str(member_id)},
        )
        return int(row["attendance_count"]) if row else 0

    @staticmethod
    def _is_depletion_auto_end(info: dict) -> bool:
        """Whether the pack's end_date may hold a depletion auto-end to
        reverse: a non-null end_date on a finite-count trial / one_time
        pack. Safe by convention: end_date is AUTOMATIC-only (a depletion
        auto-end or the purchase-stamped duration expiry — the restore
        target) — a MANUAL termination writes cancel_date, which the
        reversal never touches, so a staff-ended pack can never be
        resurrected here."""
        if info["end_date"] is None or info["class_count"] is None:
            return False
        return PlanType(info["plan_type"]) in (
            PlanType.trial,
            PlanType.one_time,
        )

    @staticmethod
    async def _fetchone(
        session: AsyncSession, sql: str, params: dict
    ) -> dict | None:
        """One row of a query as a dict, or None."""
        row = (
            (await session.execute(text(sql), params)).mappings().fetchone()
        )
        return dict(row) if row else None
