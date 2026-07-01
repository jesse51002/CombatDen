"""Create / remove a member's reservation (sign-up) for a class occurrence.

A sign-up is a reservation, NOT attendance — ``member_attendance`` is still
only written by a check-in; a signed-up member who never checks in is a
no-show, never auto-counted as attended.

``create`` first validates the sign-up target is a real, active,
non-cancelled class-day (see ``_validate_occurrence``), then resolves the
occurrence's effective ``max_capacity`` (the class's own ``max_capacity``,
overridden per-occurrence by ``class_instance_exceptions.new_max_capacity``;
NULL = unlimited, never blocks) and — when capacity is limited — reads the
same DISTINCT signed-up-or-attended union the check-in capacity gate reads
(``CheckinQueries.get_signup_or_attended_members``), so a member already
counted (a prior sign-up, or already attended via a walk-in check-in) never
double-blocks. The create write is idempotent: ON CONFLICT DO NOTHING on the
``(class_id, member_id, occurrence_date)`` unique constraint.

Validation deliberately does NOT materialize ``class_history`` — sign-ups are
routinely for future occurrences, and freezing a not-yet-started occurrence
into history this early (before anyone checks in) would be wrong. Instead it
reuses the same pure ``ClassesExpander`` engine + class-load /
exception-load reads ``CheckinClassResolver`` uses for check-in (via
``CheckinQueries.get_class_for_checkin`` / ``get_instance_exceptions`` /
``get_range_exceptions``), run with ``include_cancelled=True`` so a
cancelled day and a non-recurrence date can be told apart in the error
message.
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
from src.classes.schema.classes_expander_schema import EffectiveOccurrence
from src.classes.service.classes_expander import ClassesExpander
from src.classes.service.classes_expander_mapping import (
    to_expander_class,
    to_expander_instance,
    to_expander_range,
)
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

_CLASS_NOT_FOUND_MSG = "Class not found"
_CLASS_DELETED_MSG = "Class has been deleted"
_CLASS_INACTIVE_MSG = "Class is not active"
_GYM_NOT_FOUND_MSG = "Gym not found"
_NOT_AN_OCCURRENCE_MSG = "Not a class occurrence on that date"
_CLASS_CANCELLED_MSG = "This class is cancelled that day"
_CLASS_FULL_MSG = "Class is full"


class SignupService:
    """Creates / removes a member's reservation for a class occurrence.

    Args:
        db_pool: Injected database connection pool.
        expander: The canonical recurrence + exception expander (pure), the
            same engine ``CheckinClassResolver`` uses to resolve an occurrence.
    """

    def __init__(
        self, db_pool: DirectDatabasePool, expander: ClassesExpander
    ) -> None:
        self._db_pool = db_pool
        self._queries = CheckinQueries(db_pool)
        self._expander = expander

    async def create(
        self,
        member_id: UUID,
        gym_id: UUID,
        class_id: UUID,
        occurrence_date: date,
    ) -> SignupResponse:
        """Reserve ``member_id`` a spot on the occurrence.

        Raises:
            ValueError: "Class not found" / "Gym not found" if the class /
                gym doesn't exist; "Class has been deleted" / "Class is not
                active" if the class is soft-deleted / inactive; "Not a
                class occurrence on that date" / "This class is cancelled
                that day" if ``occurrence_date`` isn't a real, non-cancelled
                occurrence of this class; "Class is full" if the occurrence
                is at its effective ``max_capacity`` and this member isn't
                already counted (signed up or attended).
        """
        class_row = await self._validate_occurrence(
            class_id, gym_id, occurrence_date
        )
        effective_capacity = (
            class_row["exception_max_capacity"]
            if class_row["exception_max_capacity"] is not None
            else class_row["max_capacity"]
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

    # -- occurrence validation ------------------------------------------

    async def _validate_occurrence(
        self,
        class_id: UUID,
        gym_id: UUID,
        occurrence_date: date,
    ) -> dict:
        """Load + validate the sign-up target, WITHOUT materializing.

        Loads the class row (exists / active / not soft-deleted for this
        gym), then runs the expander over ``[occurrence_date,
        occurrence_date]`` to confirm a real, non-cancelled occurrence lands
        on that date. Returns the class row so the caller can read
        ``max_capacity`` / ``exception_max_capacity`` off it without a
        second read.

        Raises:
            ValueError: See ``create``'s docstring for the message set.
        """
        class_row = await self._queries.get_class_for_checkin(
            class_id, gym_id, occurrence_date
        )
        if class_row is None:
            raise ValueError(_CLASS_NOT_FOUND_MSG)
        if class_row["is_deleted"]:
            raise ValueError(_CLASS_DELETED_MSG)
        if not class_row["is_active"]:
            raise ValueError(_CLASS_INACTIVE_MSG)

        gym_tz = await self._queries.get_gym_timezone(gym_id)
        if gym_tz is None:
            raise ValueError(_GYM_NOT_FOUND_MSG)

        occurrence = await self._resolve_occurrence(
            class_row, class_id, occurrence_date, gym_tz
        )
        if occurrence is None:
            raise ValueError(_NOT_AN_OCCURRENCE_MSG)
        if occurrence.is_cancelled:
            raise ValueError(_CLASS_CANCELLED_MSG)
        return class_row

    async def _resolve_occurrence(
        self,
        class_row: dict,
        class_id: UUID,
        occurrence_date: date,
        gym_tz: str,
    ) -> EffectiveOccurrence | None:
        """Expand the class over the single day, cancelled days INCLUDED.

        ``include_cancelled=True`` (unlike ``CheckinClassResolver``'s
        single-day expand) so ``_validate_occurrence`` can distinguish a
        cancelled occurrence from a date that was never a recurrence at all
        and raise a more specific message for each.
        """
        instances = await self._queries.get_instance_exceptions(
            class_id, occurrence_date, occurrence_date
        )
        ranges = await self._queries.get_range_exceptions(
            class_id, occurrence_date, occurrence_date
        )
        occurrences = self._expander.expand(
            to_expander_class(class_row),
            [to_expander_instance(row) for row in instances],
            [to_expander_range(row) for row in ranges],
            occurrence_date,
            occurrence_date,
            gym_tz,
            include_cancelled=True,
        )
        return next(
            (
                occ
                for occ in occurrences
                if occ.effective_date == occurrence_date
            ),
            None,
        )

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
