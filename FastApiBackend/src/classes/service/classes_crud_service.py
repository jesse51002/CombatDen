"""CRUD service over ``gym_classes`` (recurrence embedded).

Reads resolve the seven per-weekday instructor slots to display names via a
join on ``gym_employees`` (see ``classes_get.sql`` / ``classes_list.sql``).
Writes go to the base table; the enum and JSONB columns are cast functionally
(``CAST(:p AS …)`` — never ``:p::type``, per the repo SQL rules).
"""

import json
import logging
from uuid import UUID

from schema.gym_class import RecurringUnit
from schema.immutable_columns import GYM_CLASSES as GYM_CLASSES_IMMUTABLE
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.classes import SQL_DIR
from src.classes.schema.classes_crud_schema import (
    GymClassCreateRequest,
    GymClassListResponse,
    GymClassResponse,
    GymClassUpdateData,
)
from src.shared.column_guard import validate_mutable_columns
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)

# Per-weekday flag column names, in week order.
_DAY_FLAGS: tuple[str, ...] = ("sun", "mon", "tue", "wed", "thu", "fri", "sat")
# Columns whose UPDATE SET assignment needs a functional cast (never :p::type).
_CAST_COLUMNS: dict[str, str] = {
    "recurring_unit": "recurring_unit",
    "allowed_plan_ids": "JSONB",
}
_BAD_SCHEDULE_MSG = (
    "Invalid class schedule: a weekly class must select at least one "
    "weekday, end_date must not precede start_date, and every instructor "
    "must be an employee of this gym."
)
_WEEKLY_NEEDS_DAY_MSG = "A weekly class must select at least one weekday"


class ClassesCrudService:
    """Gym-class catalog CRUD."""

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool

    async def create_class(
        self,
        request: GymClassCreateRequest,
    ) -> GymClassResponse:
        """Insert a new class and return it with resolved instructor names."""
        days = {flag: getattr(request, flag) for flag in _DAY_FLAGS}
        self._validate_weekly(request.recurring_unit, days)

        sql = load_sql(SQL_DIR / "classes_create.sql")
        params = self._create_params(request)
        try:
            async with self._db_pool.session() as session:
                row = (
                    (await session.execute(text(sql), params))
                    .mappings()
                    .fetchone()
                )
                await session.commit()
        except IntegrityError as exc:
            raise ValueError(_BAD_SCHEDULE_MSG) from exc

        if not row:
            raise RuntimeError("INSERT did not return a row")
        return await self.get_class(UUID(str(row["class_id"])))

    async def update_class(
        self,
        class_id: UUID,
        data: GymClassUpdateData,
    ) -> GymClassResponse:
        """Update mutable columns and return the refreshed class."""
        update_fields = data.model_dump(exclude_unset=True)
        if not update_fields:
            raise ValueError("No fields provided to update")

        validate_mutable_columns(
            GYM_CLASSES_IMMUTABLE,
            set(update_fields.keys()),
        )

        existing = await self.get_class(class_id)
        self._validate_weekly_merged(existing, update_fields)

        set_clause = ", ".join(
            self._assignment(col) for col in update_fields
        )
        sql = load_sql(
            SQL_DIR / "classes_update.sql",
            {"set_clause": set_clause},
        )
        params = self._normalize_params(update_fields)
        params["class_id"] = str(class_id)
        try:
            async with self._db_pool.session() as session:
                row = (
                    (await session.execute(text(sql), params))
                    .mappings()
                    .fetchone()
                )
                await session.commit()
        except IntegrityError as exc:
            raise ValueError(_BAD_SCHEDULE_MSG) from exc

        if not row:
            raise ValueError("Class not found")
        return await self.get_class(class_id)

    async def soft_delete_class(self, class_id: UUID) -> GymClassResponse:
        """Soft-delete a class (``is_deleted = TRUE``, ``is_active = FALSE``)."""
        sql = load_sql(SQL_DIR / "classes_soft_delete.sql")
        row = await self._db_pool.execute_with_retry(
            sql, {"class_id": str(class_id)}
        )
        if not row:
            raise ValueError("Class not found")
        return await self.get_class(class_id)

    async def get_class(self, class_id: UUID) -> GymClassResponse:
        """Read a single class with resolved per-weekday instructor names."""
        sql = load_sql(SQL_DIR / "classes_get.sql")
        async with self._db_pool.session() as session:
            row = (
                (
                    await session.execute(
                        text(sql), {"class_id": str(class_id)}
                    )
                )
                .mappings()
                .fetchone()
            )
        if not row:
            raise ValueError("Class not found")
        return GymClassResponse(**dict(row))

    async def list_classes(
        self,
        gym_id: UUID,
        include_inactive: bool = False,
    ) -> GymClassListResponse:
        """List a gym's non-deleted classes (optionally including inactive)."""
        sql = load_sql(
            SQL_DIR / "classes_list.sql",
            {"include_inactive": "TRUE" if include_inactive else "FALSE"},
        )
        async with self._db_pool.session() as session:
            rows = (
                (await session.execute(text(sql), {"gym_id": str(gym_id)}))
                .mappings()
                .all()
            )
        return GymClassListResponse(
            items=[GymClassResponse(**dict(row)) for row in rows],
        )

    # -- helpers ---------------------------------------------------------

    @staticmethod
    def _validate_weekly(
        recurring_unit: RecurringUnit,
        days: dict[str, bool],
    ) -> None:
        """Raise if a weekly class selects no weekday (the DB CHECK, up front)."""
        if recurring_unit == RecurringUnit.weekly and not any(days.values()):
            raise ValueError(_WEEKLY_NEEDS_DAY_MSG)

    def _validate_weekly_merged(
        self,
        existing: GymClassResponse,
        update_fields: dict,
    ) -> None:
        """Validate the weekly rule against the post-update merged state."""
        recurring_unit = update_fields.get(
            "recurring_unit", existing.recurring_unit
        )
        days = {
            flag: update_fields.get(flag, getattr(existing, flag))
            for flag in _DAY_FLAGS
        }
        # A None for a NOT NULL day flag is a DB error handled at write time;
        # only count real True flags here.
        self._validate_weekly(
            recurring_unit,
            {flag: bool(value) for flag, value in days.items()},
        )

    @staticmethod
    def _assignment(column: str) -> str:
        """Build one SET assignment, casting enum / JSONB columns functionally."""
        cast_type = _CAST_COLUMNS.get(column)
        if cast_type is not None:
            return f"{column} = CAST(:{column} AS {cast_type})"
        return f"{column} = :{column}"

    def _create_params(self, request: GymClassCreateRequest) -> dict:
        """Build the bind params for the INSERT."""
        params: dict = {
            "gym_id": str(request.gym_id),
            "class_name": request.class_name,
            "class_description": request.class_description,
            "class_time": request.class_time,
            "duration_minutes": request.duration_minutes,
            "recurring_unit": request.recurring_unit.value,
            "recurring_interval": request.recurring_interval,
            "start_date": request.start_date,
            "end_date": request.end_date,
            "max_capacity": request.max_capacity,
            "allowed_plan_ids": self._jsonb_uuid_array(request.allowed_plan_ids),
            "image_url": request.image_url,
            "points_worth": request.points_worth,
        }
        for flag in _DAY_FLAGS:
            params[flag] = getattr(request, flag)
            instructor = getattr(request, f"{flag}_instructor_id")
            params[f"{flag}_instructor_id"] = (
                str(instructor) if instructor is not None else None
            )
        return params

    def _normalize_params(self, update_fields: dict) -> dict:
        """Coerce update values to asyncpg-friendly bind params.

        UUIDs -> str, ``allowed_plan_ids`` -> a JSONB text array,
        ``recurring_unit`` -> its enum string value; everything else passes
        through (date / time / bool / int / str).
        """
        params: dict = {}
        for col, value in update_fields.items():
            if col == "allowed_plan_ids":
                params[col] = self._jsonb_uuid_array(value)
            elif col == "recurring_unit":
                params[col] = value.value if value is not None else None
            elif isinstance(value, UUID):
                params[col] = str(value)
            else:
                params[col] = value
        return params

    @staticmethod
    def _jsonb_uuid_array(plan_ids: list[UUID] | None) -> str | None:
        """Serialize a UUID list to a JSON text array for CAST(... AS JSONB)."""
        if plan_ids is None:
            return None
        return json.dumps([str(plan_id) for plan_id in plan_ids])
