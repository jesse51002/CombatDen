"""Remove one member's check-in from a class occurrence (reverse the award).

A thin wrapper over the shared per-member reverser (``CheckinReverser``):
verify the class belongs to the gym + load its ``points_worth``, then
delegate the actual reversal — delete the member's attendance, claw back the
awarded points (clamped at 0), remove a ``class_attended`` activity, and
reverse the auto-end on the charged pack when the removal drops it back
below capacity — to the reverser for this one member, keyed by the
occurrence's identity (``class_id``, ``original_date``). No occurrence
resolution is needed: the identity key is exactly what the caller already
addressed the occurrence by. The occurrence itself is left intact: the
class still happened, this one member just didn't attend.
"""

from datetime import date
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.checkin import SQL_DIR
from src.checkin.schema.checkin_schema import CheckinRemoveResponse
from src.checkin.service.checkin_reverser import CheckinReverser
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

_CLASS_NOT_FOUND_MSG = "Class not found"


class CheckinRemover:
    """Reverses a single member's check-in on one occurrence.

    Args:
        db_pool: Injected database connection pool.
        reverser: The shared per-member reversal core (delete attendance + claw
            back points + drop activity + reverse the pack auto-end).
    """

    def __init__(
        self, db_pool: DirectDatabasePool, reverser: CheckinReverser
    ) -> None:
        self._db_pool = db_pool
        self._reverser = reverser

    async def remove(
        self,
        class_id: UUID,
        gym_id: UUID,
        occurrence_date: date,
        member_id: UUID,
    ) -> CheckinRemoveResponse:
        """Delete the member's attendance + reverse its points / pack / activity.

        ``occurrence_date`` is the occurrence's ORIGINAL date.

        Returns a ``removed=False`` result (no error) when the member was not
        checked in.

        Raises:
            ValueError: If the class does not exist for this gym (mapped to 404).
        """
        async with self._db_pool.session() as session:
            class_row = await self._load_class(session, class_id, gym_id)
            points_worth = int(class_row["points_worth"])

            result = await self._reverser.reverse(
                session,
                member_id,
                gym_id,
                class_id,
                occurrence_date,
                points_worth,
            )
            await session.commit()

        return result

    async def _load_class(
        self, session: AsyncSession, class_id: UUID, gym_id: UUID
    ) -> dict:
        """Load the class (gym auth + points_worth); 404 on a wrong/absent gym."""
        row = await self._fetchone(
            session,
            load_sql(SQL_DIR / "checkin_load_class_for_removal.sql"),
            {"class_id": str(class_id)},
        )
        if row is None or str(row["gym_id"]) != str(gym_id):
            raise ValueError(_CLASS_NOT_FOUND_MSG)
        return row

    @staticmethod
    async def _fetchone(
        session: AsyncSession, sql: str, params: dict
    ) -> dict | None:
        """One row of a query as a dict, or None."""
        row = (
            (await session.execute(text(sql), params)).mappings().fetchone()
        )
        return dict(row) if row else None
