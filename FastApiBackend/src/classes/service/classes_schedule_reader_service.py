"""Schedule-board reader: effective dated occurrences across a date window.

For a gym + ``[start_date, end_date]`` window this loads every class (deleted
ones INCLUDED — their past renders forever), each class's full schedule
version history, and the in-window exceptions, then runs the pure
``ClassesVersionExpander`` with ``include_cancelled=True`` (so cancelled days
are shown, flagged). Past and future render from the SAME computation: the
version owning an occurrence's original slot is immutable, so the past always
re-renders identically — there is no stored-occurrence side, no
materialize-on-read, and no past/live dedup. Each occurrence is enriched with
the resolved instructor name, the per-occurrence instance/range-exception
flags, and the attendance / sign-up counts (all keyed by the occurrence's
full identity, ``(class_id, original_date, original_time)`` — two same-day
slots enrich independently).

The one time-dependent rule: a soft-DELETED class emits only occurrences that
have already ENDED (``occurred_at`` + duration at/before now) — its past is a
permanent record, but a dead class produces no in-session or future
occurrences.
"""

import asyncio
import logging
from collections import defaultdict
from datetime import UTC, date, datetime, time, timedelta
from uuid import UUID

from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.classes import SQL_DIR
from src.classes.schema.classes_crud_schema import (
    EffectiveClassInstanceListResponse,
    EffectiveClassInstanceResponse,
)
from src.classes.schema.classes_expander_schema import EffectiveOccurrence
from src.classes.service.classes_expander_mapping import (
    to_expander_instance,
    to_expander_range,
    to_expander_schedule,
)
from src.classes.service.classes_version_expander import (
    ClassesVersionExpander,
)
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)


class ClassesScheduleReaderService:
    """Builds the schedule board (effective occurrences) for a gym + window."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        version_expander: ClassesVersionExpander,
    ) -> None:
        self._db_pool = db_pool
        self._version_expander = version_expander

    async def list_effective_instances(
        self,
        gym_id: UUID,
        start_date: date,
        end_date: date,
    ) -> EffectiveClassInstanceListResponse:
        """Return every effective occurrence in the window, board-shaped.

        The independent reads run concurrently (this is the CRM's hottest
        schedule read). Cross-window reschedules are handled by WIDENING: the
        exception load also returns rows whose ``new_date`` falls in the
        window, each class expands over bounds stretched to cover its
        exceptions' original and target dates, and the occurrence set is then
        filtered back to the view window by EFFECTIVE date — so an occurrence
        moved into this window renders here (and only here), while its
        counts (keyed by the out-of-window original date) still load via the
        same widened bounds.
        """
        gym_params = {"gym_id": str(gym_id)}
        window_params = {
            "gym_id": str(gym_id),
            "start_date": start_date,
            "end_date": end_date,
        }
        classes, version_rows, instance_rows, range_rows = (
            await asyncio.gather(
                self._read_all("classes_board_classes.sql", gym_params),
                self._read_all("classes_schedules_for_gym.sql", gym_params),
                self._read_all(
                    "classes_instance_exceptions_for_window.sql",
                    window_params,
                ),
                self._read_all(
                    "classes_range_exceptions_for_window.sql", window_params
                ),
            )
        )
        versions_by_class = self._group_by_class(version_rows)
        instances_by_class = self._group_by_class(instance_rows)
        ranges_by_class = self._group_by_class(range_rows)

        count_start, count_end = self._widened_bounds(
            start_date, end_date, instance_rows
        )
        count_params = {
            "gym_id": str(gym_id),
            "start_date": count_start,
            "end_date": count_end,
        }
        instructors, attendance, signups = await asyncio.gather(
            self._instructor_names(gym_id),
            self._occurrence_counts(
                "classes_attendance_counts.sql",
                "attendance_count",
                count_params,
            ),
            self._occurrence_counts(
                "classes_signup_counts.sql", "signup_count", count_params
            ),
        )

        now = datetime.now(UTC)
        items: list[EffectiveClassInstanceResponse] = []
        for class_row in classes:
            items.extend(
                self._board_rows_for_class(
                    class_row,
                    versions_by_class.get(class_row["class_id"], []),
                    instances_by_class.get(class_row["class_id"], []),
                    ranges_by_class.get(class_row["class_id"], []),
                    start_date,
                    end_date,
                    instructors,
                    attendance,
                    signups,
                    now,
                )
            )
        items.sort(key=lambda row: row.occurred_at)
        return EffectiveClassInstanceListResponse(items=items)

    # -- per-class expansion + enrichment --------------------------------

    def _board_rows_for_class(
        self,
        class_row: dict,
        version_rows: list[dict],
        instance_rows: list[dict],
        range_rows: list[dict],
        start_date: date,
        end_date: date,
        instructors: dict[str, str],
        attendance: dict[tuple[str, date, time], int],
        signups: dict[tuple[str, date, time], int],
        now: datetime,
    ) -> list[EffectiveClassInstanceResponse]:
        """Expand one class's version history into its board rows.

        The expansion runs over bounds widened to this class's exception
        original/target dates (so a cross-window reschedule's identity date
        is enumerated), then filters back to the view window by EFFECTIVE
        date — a moved-out occurrence renders in its target window only. A
        soft-deleted class keeps only occurrences that already ENDED (its
        past is a record; a dead class has no live/future slots — the delete
        path wiped their sign-ups and check-ins).
        """
        expand_start, expand_end = self._widened_bounds(
            start_date, end_date, instance_rows
        )
        occurrences = self._version_expander.expand(
            [to_expander_schedule(row) for row in version_rows],
            [to_expander_instance(row) for row in instance_rows],
            [to_expander_range(row) for row in range_rows],
            expand_start,
            expand_end,
            include_cancelled=True,
        )
        occurrences = [
            occ
            for occ in occurrences
            if start_date <= occ.effective_date <= end_date
        ]
        if class_row["is_deleted"]:
            occurrences = [
                occ for occ in occurrences if self._has_ended(occ, now)
            ]
        # All three per-occurrence enrichments key on the FULL slot identity
        # (original_date, original_time): with several slots per day legal, a
        # date-only key would flag/override/count BOTH same-day occurrences
        # from one slot's exception or rows.
        instance_slots = {
            (row["original_date"], row["original_time"])
            for row in instance_rows
        }
        # Effective per-slot capacity: an instance exception's
        # new_max_capacity wins over the class default for its exact slot.
        # The expander resolves the time / instructor / duration overrides
        # but not capacity, and the check-in capacity gate resolves
        # new_max_capacity on its own path — so the board read resolves it
        # here too, keeping the displayed (and prefill) capacity consistent
        # with what check-in enforces.
        capacity_overrides = {
            (row["original_date"], row["original_time"]):
                row["new_max_capacity"]
            for row in instance_rows
            if row["new_max_capacity"] is not None
        }
        return [
            self._build_row(
                occ,
                class_row,
                instance_slots,
                capacity_overrides,
                range_rows,
                instructors,
                attendance,
                signups,
            )
            for occ in occurrences
        ]

    @staticmethod
    def _build_row(
        occ: EffectiveOccurrence,
        class_row: dict,
        instance_slots: set[tuple[date, time]],
        capacity_overrides: dict[tuple[date, time], int],
        range_rows: list[dict],
        instructors: dict[str, str],
        attendance: dict[tuple[str, date, time], int],
        signups: dict[tuple[str, date, time], int],
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
        slot_key = (occ.original_date, occ.original_time)
        occurrence_key = (
            str(class_row["class_id"]),
            occ.original_date,
            occ.original_time,
        )
        return EffectiveClassInstanceResponse(
            class_id=class_row["class_id"],
            gym_id=class_row["gym_id"],
            class_name=class_row["class_name"],
            class_date=occ.effective_date,
            original_date=occ.original_date,
            original_time=occ.original_time,
            occurred_at=occ.occurred_at,
            resolved_class_time=occ.class_time,
            resolved_duration_minutes=occ.duration_minutes,
            resolved_instructor_id=occ.instructor_id,
            resolved_instructor_name=instructor_name,
            image_url=class_row["image_url"],
            points_worth=class_row["points_worth"],
            max_capacity=capacity_overrides.get(
                slot_key, class_row["max_capacity"]
            ),
            is_cancelled=occ.is_cancelled,
            has_instance_exception=slot_key in instance_slots,
            has_range_exception=has_range,
            cancelling_range_id=occ.cancelling_range_id,
            attendance_count=attendance.get(occurrence_key, 0),
            signup_count=signups.get(occurrence_key, 0),
        )

    @staticmethod
    def _has_ended(occ: EffectiveOccurrence, now: datetime) -> bool:
        """Whether the occurrence is over — its start + duration is at/before
        now (the deleted-class past-only filter)."""
        end = occ.occurred_at + timedelta(minutes=occ.duration_minutes)
        return end <= now

    @staticmethod
    def _widened_bounds(
        start_date: date,
        end_date: date,
        instance_rows: list[dict],
    ) -> tuple[date, date]:
        """The window stretched to cover every exception's original AND
        target date, so reschedules crossing the window boundary are
        enumerable and their counts load."""
        bound_start, bound_end = start_date, end_date
        for row in instance_rows:
            for day in (row["original_date"], row["new_date"]):
                if day is None:
                    continue
                if day < bound_start:
                    bound_start = day
                if day > bound_end:
                    bound_end = day
        return bound_start, bound_end

    # -- loads -----------------------------------------------------------

    async def _instructor_names(self, gym_id: UUID) -> dict[str, str]:
        """Map ``employee_id`` -> ``"first_name last_name"`` for the gym."""
        rows = await self._read_all(
            "classes_gym_instructors.sql", {"gym_id": str(gym_id)}
        )
        return {
            str(row["employee_id"]): f"{row['first_name']} {row['last_name']}"
            for row in rows
        }

    async def _occurrence_counts(
        self,
        sql_file: str,
        count_column: str,
        window_params: dict,
    ) -> dict[tuple[str, date, time], int]:
        """Map ``(class_id, original_date, original_time)`` -> count, for the
        attendance and sign-up count queries (both keyed by the occurrence's
        full slot identity)."""
        rows = await self._read_all(sql_file, window_params)
        return {
            (
                str(row["class_id"]),
                row["original_date"],
                row["original_time"],
            ): row[count_column]
            for row in rows
        }

    @staticmethod
    def _group_by_class(rows: list[dict]) -> dict[object, list[dict]]:
        """Group rows by their ``class_id``."""
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
