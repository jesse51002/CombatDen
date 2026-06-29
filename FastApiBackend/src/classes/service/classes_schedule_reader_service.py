"""Schedule-board reader: effective dated occurrences across a date window.

For a gym + ``[start_date, end_date]`` window this loads every non-deleted class
and its in-window exceptions, runs the canonical ``ClassesExpander`` with
``include_cancelled=True`` (so cancelled days are shown, flagged), then enriches
each occurrence with the resolved instructor name, the per-occurrence
instance/range-exception flags, and the recorded attendance count.
"""

import logging
from collections import defaultdict
from datetime import UTC, date, datetime, time, timedelta
from uuid import UUID
from zoneinfo import ZoneInfo

from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.classes import SQL_DIR
from src.classes.schema.classes_crud_schema import (
    EffectiveClassInstanceListResponse,
    EffectiveClassInstanceResponse,
)
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

# Slack added on each side of the UTC attendance-count scan so no occurrence's
# instant can fall outside the bound regardless of the gym's UTC offset / DST.
_ATTENDANCE_BOUND_SLACK = timedelta(days=1)


class ClassesScheduleReaderService:
    """Builds the schedule board (effective occurrences) for a gym + window."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        expander: ClassesExpander,
    ) -> None:
        self._db_pool = db_pool
        self._expander = expander

    async def list_effective_instances(
        self,
        gym_id: UUID,
        start_date: date,
        end_date: date,
    ) -> EffectiveClassInstanceListResponse:
        """Return every effective occurrence in the window, board-shaped."""
        gym_tz = await self._gym_timezone(gym_id)
        classes = await self._read_all(
            "classes_load_for_window.sql",
            {
                "gym_id": str(gym_id),
                "start_date": start_date,
                "end_date": end_date,
            },
        )
        instances_by_class = self._group_by_class(
            await self._read_all(
                "classes_instance_exceptions_for_window.sql",
                {
                    "gym_id": str(gym_id),
                    "start_date": start_date,
                    "end_date": end_date,
                },
            )
        )
        ranges_by_class = self._group_by_class(
            await self._read_all(
                "classes_range_exceptions_for_window.sql",
                {
                    "gym_id": str(gym_id),
                    "start_date": start_date,
                    "end_date": end_date,
                },
            )
        )
        instructors = await self._instructor_names(gym_id)
        attendance = await self._attendance_counts(
            gym_id, start_date, end_date, gym_tz
        )

        items: list[EffectiveClassInstanceResponse] = []
        for class_row in classes:
            items.extend(
                self._board_rows_for_class(
                    class_row,
                    instances_by_class.get(class_row["class_id"], []),
                    ranges_by_class.get(class_row["class_id"], []),
                    start_date,
                    end_date,
                    gym_tz,
                    instructors,
                    attendance,
                )
            )
        items.sort(key=lambda row: row.occurred_at)
        return EffectiveClassInstanceListResponse(items=items)

    # -- per-class expansion + enrichment --------------------------------

    def _board_rows_for_class(
        self,
        class_row: dict,
        instance_rows: list[dict],
        range_rows: list[dict],
        start_date: date,
        end_date: date,
        gym_tz: str,
        instructors: dict[str, str],
        attendance: dict[tuple[str, datetime], int],
    ) -> list[EffectiveClassInstanceResponse]:
        """Expand one class and enrich each occurrence into a board row."""
        occurrences = self._expander.expand(
            to_expander_class(class_row),
            [to_expander_instance(row) for row in instance_rows],
            [to_expander_range(row) for row in range_rows],
            start_date,
            end_date,
            gym_tz,
            include_cancelled=True,
        )
        instance_dates = {row["original_date"] for row in instance_rows}
        return [
            self._build_row(
                occ,
                class_row,
                instance_dates,
                range_rows,
                instructors,
                attendance,
            )
            for occ in occurrences
        ]

    @staticmethod
    def _build_row(
        occ: EffectiveOccurrence,
        class_row: dict,
        instance_dates: set[date],
        range_rows: list[dict],
        instructors: dict[str, str],
        attendance: dict[tuple[str, datetime], int],
    ) -> EffectiveClassInstanceResponse:
        """Assemble one enriched board row from an effective occurrence."""
        instructor_name = (
            instructors.get(str(occ.instructor_id))
            if occ.instructor_id is not None
            else None
        )
        has_range = any(
            row["start_date"] <= occ.original_date <= row["end_date"]
            for row in range_rows
        )
        count = attendance.get((str(class_row["class_id"]), occ.occurred_at))
        return EffectiveClassInstanceResponse(
            class_id=class_row["class_id"],
            gym_id=class_row["gym_id"],
            class_name=class_row["class_name"],
            class_date=occ.effective_date,
            occurred_at=occ.occurred_at,
            resolved_class_time=occ.class_time,
            resolved_duration_minutes=occ.duration_minutes,
            resolved_instructor_id=occ.instructor_id,
            resolved_instructor_name=instructor_name,
            image_url=class_row["image_url"],
            points_worth=class_row["points_worth"],
            max_capacity=class_row["max_capacity"],
            is_cancelled=occ.is_cancelled,
            has_instance_exception=occ.original_date in instance_dates,
            has_range_exception=has_range,
            attendance_count=count,
        )

    # -- loads -----------------------------------------------------------

    async def _gym_timezone(self, gym_id: UUID) -> str:
        """Read the gym's IANA timezone (for the expand + attendance bounds)."""
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

    async def _instructor_names(self, gym_id: UUID) -> dict[str, str]:
        """Map ``employee_id`` -> ``"first_name last_name"`` for the gym."""
        rows = await self._read_all(
            "classes_gym_instructors.sql", {"gym_id": str(gym_id)}
        )
        return {
            str(row["employee_id"]): f"{row['first_name']} {row['last_name']}"
            for row in rows
        }

    async def _attendance_counts(
        self,
        gym_id: UUID,
        start_date: date,
        end_date: date,
        gym_tz: str,
    ) -> dict[tuple[str, datetime], int]:
        """Map ``(class_id, occurred_at)`` -> recorded attendance count."""
        tz = ZoneInfo(gym_tz)
        lower = (
            datetime.combine(start_date, time.min, tzinfo=tz).astimezone(UTC)
            - _ATTENDANCE_BOUND_SLACK
        )
        upper = (
            datetime.combine(end_date, time.max, tzinfo=tz).astimezone(UTC)
            + _ATTENDANCE_BOUND_SLACK
        )
        rows = await self._read_all(
            "classes_attendance_counts.sql",
            {"gym_id": str(gym_id), "lower": lower, "upper": upper},
        )
        return {
            (str(row["class_id"]), row["occurred_at"]): row["attendance_count"]
            for row in rows
        }

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
