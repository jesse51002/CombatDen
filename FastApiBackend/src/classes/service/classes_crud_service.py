"""CRUD service over the class IDENTITY + versioned SCHEDULE pair.

A class is a ``gym_classes`` identity row plus append-only
``gym_class_schedules`` versions (the schedule shape). Create writes the
identity and mints the FIRST version in one transaction; update splits by
destination — identity fields UPDATE in place, a submitted schedule shape
mints a NEW version (running the version-change wipe) via
``ClassesVersionsService``, both halves in ONE transaction. Soft delete flips
the flags AND runs the future-keyed wipe (a deleted class produces no future
slots). Reads flatten identity + the CURRENT version
(``gym_class_schedules_current``); each ``weekday_slots`` slot's instructor
resolves to a display name via ONE ``gym_employees`` lookup merged in Python
(no per-slot joins), so the response shape is the same flat class the CRM
form edits. Slot-shape validation (weekly needs a weekday, no dupe times,
key-per-unit rules) lives in the shared Pydantic canonicalizer on
``GymClassScheduleFields`` — a bad shape 422s before this service runs. The
JSONB / enum columns are cast functionally — always ``CAST(:p AS …)``, never
a ``::`` cast on a bind param, per the repo SQL rules.
"""

import json
import logging
from uuid import UUID

from schema.immutable_columns import GYM_CLASSES as GYM_CLASSES_IMMUTABLE
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.classes import SQL_DIR
from src.classes.schema.classes_crud_schema import (
    ClassSlotResponse,
    GymClassCreateRequest,
    GymClassIdentityUpdateData,
    GymClassListResponse,
    GymClassResponse,
    GymClassScheduleFields,
)
from src.classes.service.classes_versions_service import (
    ClassesVersionsService,
)
from src.shared.column_guard import validate_mutable_columns
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)

# Identity columns whose UPDATE SET assignment needs a functional cast.
_CAST_COLUMNS: dict[str, str] = {
    "allowed_plan_ids": "JSONB",
}
_BAD_SCHEDULE_MSG = (
    "Invalid class schedule: end_date must not precede start_date, and "
    "every slot instructor must be an employee of this gym."
)
_BAD_IDENTITY_MSG = "Invalid class fields."
_CLASS_NOT_FOUND_MSG = "Class not found"


class ClassesCrudService:
    """Gym-class catalog CRUD (identity + versioned schedule)."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        versions_service: ClassesVersionsService,
    ) -> None:
        self._db_pool = db_pool
        self._versions_service = versions_service

    async def create_class(
        self,
        request: GymClassCreateRequest,
    ) -> GymClassResponse:
        """Insert the identity row and mint the first schedule version, in one
        transaction; return the flattened class."""
        shape = GymClassScheduleFields(
            **request.model_dump(
                include=set(GymClassScheduleFields.model_fields)
            )
        )

        sql = load_sql(SQL_DIR / "classes_create.sql")
        params = self._identity_create_params(request)
        try:
            async with self._db_pool.session() as session:
                timezone = await self._versions_service.gym_timezone(
                    session, request.gym_id
                )
                row = (
                    (await session.execute(text(sql), params))
                    .mappings()
                    .fetchone()
                )
                if not row:
                    raise RuntimeError("INSERT did not return a row")
                class_id = UUID(str(row["class_id"]))
                await self._versions_service.mint(
                    session, class_id, request.gym_id, shape, timezone
                )
                await session.commit()
        except IntegrityError as exc:
            raise ValueError(_BAD_SCHEDULE_MSG) from exc

        return await self.get_class(class_id)

    async def update_class(
        self,
        class_id: UUID,
        identity: GymClassIdentityUpdateData | None,
        schedule: GymClassScheduleFields | None,
    ) -> GymClassResponse:
        """Apply the split update — identity in place, schedule as a new
        version (+ wipe) — in ONE transaction; return the refreshed class."""
        identity_fields = (
            identity.model_dump(exclude_unset=True) if identity else {}
        )
        if not identity_fields and schedule is None:
            raise ValueError("No fields provided to update")
        if identity_fields:
            validate_mutable_columns(
                GYM_CLASSES_IMMUTABLE, set(identity_fields.keys())
            )

        gym_id = await self._gym_id_of(class_id)
        try:
            async with self._db_pool.session() as session:
                if identity_fields:
                    await self._update_identity(
                        session, class_id, identity_fields
                    )
                if schedule is not None:
                    timezone = await self._versions_service.gym_timezone(
                        session, gym_id
                    )
                    await self._versions_service.mint(
                        session, class_id, gym_id, schedule, timezone
                    )
                await session.commit()
        except IntegrityError as exc:
            raise ValueError(_BAD_SCHEDULE_MSG) from exc

        return await self.get_class(class_id)

    async def soft_delete_class(self, class_id: UUID) -> GymClassResponse:
        """Soft-delete a class (``is_deleted = TRUE``, ``is_active = FALSE``)
        AND wipe its future-keyed rows — future sign-ups deleted, early
        check-ins reversed with points clawed back, future instance
        exceptions dropped — in one transaction. Wipe FIRST: its points load
        reads the still-live class row. Past occurrences render forever."""
        gym_id = await self._gym_id_of(class_id)
        async with self._db_pool.session() as session:
            await self._versions_service.wipe_all_future(
                session, class_id, gym_id
            )
            row = (
                (
                    await session.execute(
                        text(load_sql(SQL_DIR / "classes_soft_delete.sql")),
                        {"class_id": str(class_id)},
                    )
                )
                .mappings()
                .fetchone()
            )
            if not row:
                raise ValueError(_CLASS_NOT_FOUND_MSG)
            await session.commit()
        return await self._get_class_any(class_id)

    async def get_class(self, class_id: UUID) -> GymClassResponse:
        """Read one class flattened with its CURRENT schedule version and
        resolved per-weekday instructor names."""
        return await self._get_class_any(class_id)

    async def list_classes(
        self,
        gym_id: UUID,
        include_inactive: bool = False,
    ) -> GymClassListResponse:
        """List a gym's non-deleted classes (optionally including inactive),
        each flattened with its current schedule version."""
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
            names = await self._instructor_names(
                session, [dict(row) for row in rows]
            )
        return GymClassListResponse(
            items=[self._to_response(dict(row), names) for row in rows],
        )

    # -- helpers ---------------------------------------------------------

    async def _get_class_any(self, class_id: UUID) -> GymClassResponse:
        """The flattened read, deleted classes included (the soft-delete
        response still shows the class it just deleted)."""
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
                raise ValueError(_CLASS_NOT_FOUND_MSG)
            names = await self._instructor_names(session, [dict(row)])
        return self._to_response(dict(row), names)

    async def _instructor_names(
        self,
        session: AsyncSession,
        rows: list[dict],
    ) -> dict[str, str]:
        """One employee-name lookup for every distinct instructor id across
        the rows' ``weekday_slots`` — the merge replaces the old seven
        per-weekday joins."""
        ids = {
            slot["instructor_id"]
            for row in rows
            for slots in row["weekday_slots"].values()
            for slot in slots
            if slot["instructor_id"] is not None
        }
        if not ids:
            return {}
        name_rows = (
            (
                await session.execute(
                    text(
                        load_sql(SQL_DIR / "classes_instructor_names.sql")
                    ),
                    {"employee_ids": [str(employee_id) for employee_id in ids]},
                )
            )
            .mappings()
            .all()
        )
        return {
            str(name_row["employee_id"]): name_row["instructor_name"]
            for name_row in name_rows
        }

    @staticmethod
    def _to_response(row: dict, names: dict[str, str]) -> GymClassResponse:
        """Assemble the response: the flat row plus ``weekday_slots`` with
        each slot's instructor name merged in."""
        weekday_slots = {
            day: [
                ClassSlotResponse(
                    time=slot["time"],
                    instructor_id=slot["instructor_id"],
                    instructor_name=(
                        names.get(str(slot["instructor_id"]))
                        if slot["instructor_id"] is not None
                        else None
                    ),
                )
                for slot in slots
            ]
            for day, slots in row["weekday_slots"].items()
        }
        return GymClassResponse(
            **{**row, "weekday_slots": weekday_slots}
        )

    async def _gym_id_of(self, class_id: UUID) -> UUID:
        """The class's gym (a live class only) — 404 when absent/deleted."""
        async with self._db_pool.session() as session:
            row = (
                (
                    await session.execute(
                        text(load_sql(SQL_DIR / "classes_load_one.sql")),
                        {"class_id": str(class_id)},
                    )
                )
                .mappings()
                .fetchone()
            )
        if not row:
            raise ValueError(_CLASS_NOT_FOUND_MSG)
        return row["gym_id"]

    async def _update_identity(
        self,
        session,
        class_id: UUID,
        identity_fields: dict,
    ) -> None:
        """UPDATE the provided identity columns in the caller's transaction."""
        set_clause = ", ".join(
            self._assignment(col) for col in identity_fields
        )
        sql = load_sql(
            SQL_DIR / "classes_update.sql",
            {"set_clause": set_clause},
        )
        params = self._normalize_params(identity_fields)
        params["class_id"] = str(class_id)
        row = (
            (await session.execute(text(sql), params)).mappings().fetchone()
        )
        if not row:
            raise ValueError(_CLASS_NOT_FOUND_MSG)

    @staticmethod
    def _assignment(column: str) -> str:
        """Build one SET assignment, casting JSONB columns functionally."""
        cast_type = _CAST_COLUMNS.get(column)
        if cast_type is not None:
            return f"{column} = CAST(:{column} AS {cast_type})"
        return f"{column} = :{column}"

    def _identity_create_params(
        self, request: GymClassCreateRequest
    ) -> dict:
        """Bind params for the identity INSERT."""
        return {
            "gym_id": str(request.gym_id),
            "class_name": request.class_name,
            "class_description": request.class_description,
            "max_capacity": request.max_capacity,
            "allowed_plan_ids": self._jsonb_uuid_array(
                request.allowed_plan_ids
            ),
            "image_url": request.image_url,
            "points_worth": request.points_worth,
        }

    def _normalize_params(self, update_fields: dict) -> dict:
        """Coerce identity update values to asyncpg-friendly bind params."""
        params: dict = {}
        for col, value in update_fields.items():
            if col == "allowed_plan_ids":
                params[col] = self._jsonb_uuid_array(value)
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
