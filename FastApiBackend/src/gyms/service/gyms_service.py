"""Gyms domain service: create gym + owner employee, get gym, update gym."""

import logging
from uuid import UUID

from schema.immutable_columns import GYMS as GYMS_IMMUTABLE
from sqlalchemy import text

from src.gyms import SQL_DIR
from src.gyms.schema.gyms_schema import (
    GymCreateRequest,
    GymCreateResponse,
    GymEmployeeResponse,
    GymResponse,
    GymUpdateData,
)
from src.shared.column_guard import validate_mutable_columns
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)


class GymsService:
    """Create / get / update gyms.

    Args:
        db_pool: Injected database connection pool.
    """

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool

    async def create_gym(
        self,
        request: GymCreateRequest,
        user_id: UUID,
    ) -> GymCreateResponse:
        """Create a gym and the calling user's owner gym_employees row.

        Both inserts happen in a single transaction so a partial
        create cannot leave a gym without an owner.
        """
        async with self._db_pool.session() as session:
            gym_row = (
                (
                    await session.execute(
                        text(load_sql(SQL_DIR / "insert_gym.sql")),
                        {
                            "gym_name": request.gym_name,
                            "gym_description": request.gym_description,
                            "timezone": request.timezone,
                        },
                    )
                )
                .mappings()
                .fetchone()
            )

            owner_row = (
                (
                    await session.execute(
                        text(load_sql(SQL_DIR / "insert_owner_employee.sql")),
                        {
                            "gym_id": gym_row["gym_id"],
                            "user_id": str(user_id),
                            "first_name": request.owner_first_name,
                            "last_name": request.owner_last_name,
                            "phone": request.owner_phone,
                            "email": request.owner_email,
                        },
                    )
                )
                .mappings()
                .fetchone()
            )

            await session.commit()

        return GymCreateResponse(
            gym=GymResponse(**gym_row),
            owner=GymEmployeeResponse(**owner_row),
        )

    async def get_gym_for_user(self, user_id: UUID) -> GymResponse:
        """Return the caller's gym (looked up via gym_employees)."""
        async with self._db_pool.session() as session:
            row = (
                (
                    await session.execute(
                        text(load_sql(SQL_DIR / "get_gym_for_user.sql")),
                        {"user_id": str(user_id)},
                    )
                )
                .mappings()
                .fetchone()
            )

        if not row:
            raise ValueError("No gym found for this user")

        return GymResponse(**row)

    async def update_gym(
        self,
        gym_id: UUID,
        data: GymUpdateData,
    ) -> GymResponse:
        """Update mutable fields on a gym row."""
        update_fields = data.model_dump(exclude_unset=True, exclude_none=True)

        if not update_fields:
            raise ValueError("No fields provided to update")

        validate_mutable_columns(GYMS_IMMUTABLE, set(update_fields.keys()))

        set_clause = ", ".join(f"{col} = :{col}" for col in update_fields)
        sql = load_sql(
            SQL_DIR / "update_gym.sql",
            {"set_clause": set_clause},
        )

        params = {**update_fields, "gym_id": str(gym_id)}
        row = await self._db_pool.execute_with_retry(sql, params)

        if not row:
            raise ValueError("Gym not found")

        return GymResponse(**row)
