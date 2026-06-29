"""Lazy find-or-create of ``class_history`` occurrence rows.

The single place a ``class_history`` row is materialized for an effective class
occurrence. Used by the check-in resolve seam (and Phase 4b's batch
materialize) to turn an effective ``(class, occurred_at)`` occurrence into a
persisted row without a race: the
``INSERT ... ON CONFLICT ON CONSTRAINT uq_class_history_occurrence DO NOTHING``
arbitrates concurrent materializes, and a losing INSERT falls back to SELECTing
the row the winner created (``classes_history_find.sql``).
"""

from datetime import datetime
from uuid import UUID

from sqlalchemy import text

from src.classes import SQL_DIR
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql


class ClassesMaterializer:
    """Find-or-create the ``class_history`` row for one class occurrence.

    Args:
        db_pool: Injected database connection pool.
    """

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool

    async def find_or_create_history(
        self,
        class_id: UUID,
        gym_id: UUID,
        occurred_at: datetime,
        instructor_id: UUID | None,
        duration_minutes: int,
    ) -> tuple[UUID, bool]:
        """Return ``(class_history_id, was_created)`` for the occurrence.

        Idempotent and race-safe: the ``uq_class_history_occurrence`` UNIQUE
        (class_id, occurred_at) constraint arbitrates concurrent materializes.

        Args:
            class_id: The class the occurrence belongs to.
            gym_id: The owning gym.
            occurred_at: The occurrence's UTC, timezone-aware start instant.
            instructor_id: Effective instructor for the occurrence (or None).
            duration_minutes: Effective length of the occurrence in minutes.

        Returns:
            The ``class_history_id`` and ``was_created`` — True only when THIS
            call inserted the row (a conflicting call gets the existing id with
            False).

        Raises:
            RuntimeError: If the row is missing after an ON CONFLICT DO NOTHING
                (should never happen — the conflict implies an existing row).
        """
        insert_sql = load_sql(SQL_DIR / "classes_materialize_history.sql")
        params = {
            "class_id": str(class_id),
            "gym_id": str(gym_id),
            "occurred_at": occurred_at,
            "instructor_id": (
                str(instructor_id) if instructor_id is not None else None
            ),
            "duration_minutes": duration_minutes,
        }

        async with self._db_pool.session() as session:
            inserted = (
                (await session.execute(text(insert_sql), params))
                .mappings()
                .fetchone()
            )
            if inserted is not None:
                await session.commit()
                return inserted["class_history_id"], True

            find_sql = load_sql(SQL_DIR / "classes_history_find.sql")
            existing = (
                (
                    await session.execute(
                        text(find_sql),
                        {
                            "class_id": str(class_id),
                            "occurred_at": occurred_at,
                        },
                    )
                )
                .mappings()
                .fetchone()
            )
            await session.commit()

        if existing is None:
            raise RuntimeError(
                "class_history row missing after ON CONFLICT DO NOTHING"
            )
        return existing["class_history_id"], False
