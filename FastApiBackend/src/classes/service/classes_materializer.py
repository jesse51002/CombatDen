"""The ONE range-parameterized entry point that materializes ``class_history``
rows, plus the single-occurrence primitive it's built on.

``find_or_create_history`` is the low-level, race-safe find-or-create for ONE
``(class_id, occurred_at)`` occurrence: the
``INSERT ... ON CONFLICT ON CONSTRAINT uq_class_history_occurrence DO NOTHING``
arbitrates concurrent materializes, and a losing INSERT falls back to SELECTing
the row the winner created (``classes_history_find.sql``).

``materialize`` is the single place every caller — the check-in resolve seam,
the schedule board, and the reconciler sweep — materializes rows for a date
range: it owns the load (a gym's non-deleted classes + their in-window
instance/range exceptions + the gym timezone), the pure expand (via the
canonical ``ClassesExpander``), and the per-occurrence
``find_or_create_history`` write — isolating errors per class and per
occurrence so one bad class or one failed insert never aborts the rest.
Cancelled occurrences are never materialized (the expander drops them by
default). A shared forward cutoff (``future_hours``, injected — see below)
caps how far ahead of "now" an occurrence may be materialized, regardless of
how far the caller's own ``end_date`` reaches: an occurrence past the cutoff
is simply left for a later call. This is what lets the schedule board pass its
own (possibly far-future) display window straight through without eagerly
freezing not-yet-started classes' editable fields (time / instructor) into
history too early — only occurrences already ended, in session, or within the
cutoff are written. ``find_or_create_history`` itself has no such cutoff: a
caller that already knows the exact occurrence it needs (check-in) can always
force it via that primitive directly.

``materialize_current`` is the reconciler sweep's convenience wrapper:
``materialize(gym_id, today - lookback_days, today + future window)``.

``future_hours`` and ``lookback_days`` are constructor-injected (from
``Settings.materialize_future_hours`` / ``Settings.class_history_lookback_days``
via the DI container) rather than read from a module-level ``settings``
import, so this service never imports ``settings`` directly.
"""

import logging
from collections import defaultdict
from datetime import UTC, date, datetime, timedelta
from uuid import UUID

from sqlalchemy import text

from src.classes import SQL_DIR
from src.classes.schema.classes_expander_schema import EffectiveOccurrence
from src.classes.service.classes_expander import ClassesExpander
from src.classes.service.classes_expander_mapping import (
    to_expander_class,
    to_expander_instance,
    to_expander_range,
)
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)


class ClassesMaterializer:
    """Find-or-create ``class_history`` rows, single-occurrence or range-wide.

    Args:
        db_pool: Injected database connection pool.
        expander: The canonical recurrence + exception expander (pure).
        future_hours: How far ahead of "now" ``materialize`` will write an
            occurrence (``Settings.materialize_future_hours``).
        lookback_days: The past side of ``materialize_current``'s window
            (``Settings.class_history_lookback_days``). <= 0 makes
            ``materialize_current`` a no-op.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        expander: ClassesExpander,
        future_hours: int,
        lookback_days: int,
    ) -> None:
        self._db_pool = db_pool
        self._expander = expander
        self._future_hours = future_hours
        self._lookback_days = lookback_days

    # -- the single-occurrence primitive ----------------------------------

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
        Used both directly (a caller that already knows the exact occurrence,
        e.g. check-in's final id lookup) and internally by ``materialize``.

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

    # -- the range entry point ---------------------------------------------

    async def materialize(
        self,
        gym_id: UUID,
        start_date: date,
        end_date: date,
    ) -> int:
        """Materialize every non-cancelled occurrence of the gym's classes in
        ``[start_date, end_date]`` that starts no later than ``future_hours``
        ahead of now.

        Per-class and per-occurrence isolated: a bad class (unknown timezone,
        mapping error) or a failed insert is logged and skipped, never
        aborting the rest of the call. Idempotent — re-running over the same
        (or an overlapping) range returns 0 for occurrences already
        materialized.

        Returns:
            The count of occurrences NEWLY created by this call (0 on a fully
            idempotent re-run).
        """
        cutoff = datetime.now(UTC) + timedelta(hours=self._future_hours)
        classes = await self._load_classes(gym_id, start_date, end_date)
        if not classes:
            return 0

        gym_tz = await self._gym_timezone(gym_id)
        instances_by_class = self._group_by_class(
            await self._load_instance_exceptions(
                gym_id, start_date, end_date
            )
        )
        ranges_by_class = self._group_by_class(
            await self._load_range_exceptions(gym_id, start_date, end_date)
        )

        created = 0
        for class_row in classes:
            created += await self._materialize_class(
                class_row,
                instances_by_class.get(class_row["class_id"], []),
                ranges_by_class.get(class_row["class_id"], []),
                start_date,
                end_date,
                gym_tz,
                cutoff,
            )
        return created

    async def materialize_current(self, gym_id: UUID) -> int:
        """Convenience: ``materialize(gym, today - lookback_days, today +
        future window)`` — the reconciler sweep's per-gym call.

        A non-positive ``lookback_days`` is a no-op (no load, no write) —
        there is nothing to look back on.
        """
        if self._lookback_days <= 0:
            logger.warning(
                "materialize_current: lookback_days=%d (<= 0); skipping",
                self._lookback_days,
            )
            return 0
        now = datetime.now(UTC)
        start_date = now.date() - timedelta(days=self._lookback_days)
        end_date = (now + timedelta(hours=self._future_hours)).date()
        return await self.materialize(gym_id, start_date, end_date)

    # -- per-class expand + materialize -------------------------------------

    async def _materialize_class(
        self,
        class_row: dict,
        instance_rows: list[dict],
        range_rows: list[dict],
        start_date: date,
        end_date: date,
        gym_tz: str,
        cutoff: datetime,
    ) -> int:
        """Expand one class and materialize each occurrence up to ``cutoff``.

        The whole expansion is isolated: a bad class row (e.g. an unknown
        timezone) counts as skipped and never aborts the caller's loop.
        """
        try:
            occurrences = self._expander.expand(
                to_expander_class(class_row),
                [to_expander_instance(row) for row in instance_rows],
                [to_expander_range(row) for row in range_rows],
                start_date,
                end_date,
                gym_tz,
            )
        except Exception:
            logger.warning(
                "materialize: expand failed for class %s",
                class_row.get("class_id"),
                exc_info=True,
            )
            return 0

        created = 0
        for occ in occurrences:
            if occ.occurred_at > cutoff:
                continue  # beyond the forward window -- leave for later
            if await self._materialize_occurrence(class_row, occ):
                created += 1
        return created

    async def _materialize_occurrence(
        self,
        class_row: dict,
        occ: EffectiveOccurrence,
    ) -> bool:
        """Find-or-create one occurrence's history row; True if newly created."""
        try:
            _, was_created = await self.find_or_create_history(
                class_row["class_id"],
                class_row["gym_id"],
                occ.occurred_at,
                occ.instructor_id,
                occ.duration_minutes,
            )
        except Exception:
            logger.warning(
                "materialize: insert failed for class %s @ %s",
                class_row.get("class_id"),
                occ.occurred_at,
                exc_info=True,
            )
            return False
        return was_created

    # -- loads ---------------------------------------------------------------

    async def _gym_timezone(self, gym_id: UUID) -> str:
        """Read the gym's IANA timezone (for the expander's UTC conversion)."""
        async with self._db_pool.session() as session:
            row = (
                (
                    await session.execute(
                        text(load_sql(SQL_DIR / "get_gym_timezone.sql")),
                        {"gym_id": str(gym_id)},
                    )
                )
                .mappings()
                .fetchone()
            )
        if not row:
            raise ValueError("Gym not found")
        return row["timezone"]

    async def _load_classes(
        self,
        gym_id: UUID,
        start_date: date,
        end_date: date,
    ) -> list[dict]:
        """Every non-deleted class of the gym whose recurrence can overlap
        the window (shared with the schedule board's own load)."""
        return await self._read_all(
            "classes_load_for_window.sql",
            {
                "gym_id": str(gym_id),
                "start_date": start_date,
                "end_date": end_date,
            },
        )

    async def _load_instance_exceptions(
        self,
        gym_id: UUID,
        start_date: date,
        end_date: date,
    ) -> list[dict]:
        """Instance exceptions whose original_date falls in the window."""
        return await self._read_all(
            "classes_instance_exceptions_for_window.sql",
            {
                "gym_id": str(gym_id),
                "start_date": start_date,
                "end_date": end_date,
            },
        )

    async def _load_range_exceptions(
        self,
        gym_id: UUID,
        start_date: date,
        end_date: date,
    ) -> list[dict]:
        """Range exceptions overlapping the window."""
        return await self._read_all(
            "classes_range_exceptions_for_window.sql",
            {
                "gym_id": str(gym_id),
                "start_date": start_date,
                "end_date": end_date,
            },
        )

    @staticmethod
    def _group_by_class(rows: list[dict]) -> dict[object, list[dict]]:
        """Group exception rows by their ``class_id``."""
        grouped: dict[object, list[dict]] = defaultdict(list)
        for row in rows:
            grouped[row["class_id"]].append(row)
        return grouped

    async def _read_all(self, sql_file: str, params: dict) -> list[dict]:
        sql = load_sql(SQL_DIR / sql_file)
        async with self._db_pool.session() as session:
            rows = (
                (await session.execute(text(sql), params)).mappings().all()
            )
        return [dict(row) for row in rows]
