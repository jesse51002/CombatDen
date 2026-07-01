"""Create / remove a member's reservation (sign-up) for a class occurrence.

A sign-up is a reservation, NOT attendance — ``member_attendance`` is still
only written by a check-in; a signed-up member who never checks in is a
no-show, never auto-counted as attended.

``create`` resolves the occurrence's effective ``max_capacity`` (the class's
own ``max_capacity``, overridden per-occurrence by
``class_instance_exceptions.new_max_capacity``; NULL = unlimited, never
blocks), then — when capacity is limited — reads the same DISTINCT
signed-up-or-attended union the check-in capacity gate reads
(``CheckinQueries.get_signup_or_attended_members``), so a member already
counted (a prior sign-up, or already attended via a walk-in check-in) never
double-blocks against their own presence. The create write is idempotent: ON
CONFLICT DO NOTHING on the ``(class_id, member_id, occurrence_date)`` unique
constraint.
"""

from datetime import date
from uuid import UUID

from sqlalchemy import text

from src.checkin import SQL_DIR
from src.checkin.schema.signup_schema import (
    SignupRemoveResponse,
    SignupResponse,
)
from src.checkin.service.checkin_queries import CheckinQueries
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

_CLASS_NOT_FOUND_MSG = "Class not found"
_CLASS_FULL_MSG = "Class is full"


class SignupService:
    """Creates / removes a member's reservation for a class occurrence.

    Args:
        db_pool: Injected database connection pool.
    """

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool
        self._queries = CheckinQueries(db_pool)

    async def create(
        self,
        member_id: UUID,
        gym_id: UUID,
        class_id: UUID,
        occurrence_date: date,
    ) -> SignupResponse:
        """Reserve ``member_id`` a spot on the occurrence.

        Raises:
            ValueError: "Class not found" if the class doesn't belong to this
                gym; "Class is full" if the occurrence is at its effective
                ``max_capacity`` and this member isn't already counted (signed
                up or attended).
        """
        effective_capacity = await self._effective_capacity(
            class_id, gym_id, occurrence_date
        )
        if effective_capacity is not None:
            await self._enforce_capacity(
                class_id, gym_id, occurrence_date, member_id, effective_capacity
            )
        return await self._insert(member_id, gym_id, class_id, occurrence_date)

    async def remove(
        self,
        member_id: UUID,
        gym_id: UUID,
        class_id: UUID,
        occurrence_date: date,
    ) -> SignupRemoveResponse:
        """Delete the member's sign-up for the occurrence, if any."""
        sql = load_sql(SQL_DIR / "signup_delete.sql")
        async with self._db_pool.session() as session:
            row = (
                (
                    await session.execute(
                        text(sql),
                        {
                            "class_id": str(class_id),
                            "member_id": str(member_id),
                            "occurrence_date": occurrence_date,
                        },
                    )
                )
                .mappings()
                .fetchone()
            )
            await session.commit()
        return SignupRemoveResponse(removed=row is not None)

    # -- write -------------------------------------------------------------

    async def _insert(
        self,
        member_id: UUID,
        gym_id: UUID,
        class_id: UUID,
        occurrence_date: date,
    ) -> SignupResponse:
        """ON CONFLICT DO NOTHING create; falls back to a lookup on repeat.

        Both statements run in the same session/transaction, committed once.
        """
        insert_sql = load_sql(SQL_DIR / "signup_insert.sql")
        existing_sql = load_sql(SQL_DIR / "signup_load_existing.sql")
        params = {
            "gym_id": str(gym_id),
            "class_id": str(class_id),
            "member_id": str(member_id),
            "occurrence_date": occurrence_date,
        }

        async with self._db_pool.session() as session:
            row = (
                (await session.execute(text(insert_sql), params))
                .mappings()
                .fetchone()
            )
            if row is not None:
                await session.commit()
                return SignupResponse(
                    signup_id=row["signup_id"], already_signed_up=False
                )

            existing = (
                (await session.execute(text(existing_sql), params))
                .mappings()
                .fetchone()
            )
            if existing is None:
                raise RuntimeError(
                    "Sign-up row missing after ON CONFLICT DO NOTHING"
                )
            await session.commit()
            return SignupResponse(
                signup_id=existing["signup_id"], already_signed_up=True
            )

    # -- capacity ------------------------------------------------------------

    async def _effective_capacity(
        self, class_id: UUID, gym_id: UUID, occurrence_date: date
    ) -> int | None:
        """The occurrence's effective ``max_capacity`` (None = unlimited).

        Raises:
            ValueError: "Class not found" if the class doesn't belong to this
                gym.
        """
        sql = load_sql(SQL_DIR / "signup_load_effective_capacity.sql")
        async with self._db_pool.session() as session:
            row = (
                (
                    await session.execute(
                        text(sql),
                        {
                            "class_id": str(class_id),
                            "gym_id": str(gym_id),
                            "occurrence_date": occurrence_date,
                        },
                    )
                )
                .mappings()
                .fetchone()
            )
        if row is None:
            raise ValueError(_CLASS_NOT_FOUND_MSG)
        return (
            row["exception_max_capacity"]
            if row["exception_max_capacity"] is not None
            else row["max_capacity"]
        )

    async def _enforce_capacity(
        self,
        class_id: UUID,
        gym_id: UUID,
        occurrence_date: date,
        member_id: UUID,
        effective_capacity: int,
    ) -> None:
        """Reject when adding ``member_id`` would exceed capacity.

        A member already counted (a prior sign-up, or already attended via a
        walk-in check-in) never blocks on their own presence — this is what
        keeps the sign-up path and the check-in capacity gate consistent.

        Raises:
            ValueError: "Class is full".
        """
        members = await self._queries.get_signup_or_attended_members(
            class_id, gym_id, occurrence_date
        )
        if member_id in members:
            return
        if len(members) >= effective_capacity:
            raise ValueError(_CLASS_FULL_MSG)
