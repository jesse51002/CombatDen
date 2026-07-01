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
``(class_id, member_id, original_date)`` unique constraint, stamping
``original_time`` from the resolved occurrence.

Occurrence resolution reuses the same pure ``ClassesVersionExpander`` engine
+ schedule-version / exception reads ``CheckinClassResolver`` uses for
check-in (via ``CheckinQueries``), run with ``include_cancelled=True`` so a
cancelled day and a non-recurrence date can be told apart in the error
message. The resolution algorithm (including the reschedule-window-widening
fix) is duplicated from ``CheckinClassResolver`` rather than shared through a
facade — see that module's docstring for why a bare
``[occurrence_date, occurrence_date]`` window isn't enough on its own; the
checkin domain deliberately has no facade, so each occurrence-addressed
caller resolves its own way.
"""

from datetime import date, time
from uuid import UUID

from sqlalchemy import text

from src.checkin import SQL_DIR
from src.checkin.schema.signup_schema import (
    SignupRemoveResponse,
    SignupResponse,
)
from src.checkin.service.checkin_queries import CheckinQueries
from src.classes.schema.classes_expander_schema import EffectiveOccurrence
from src.classes.service.classes_expander_mapping import (
    to_expander_instance,
    to_expander_range,
    to_expander_schedule,
)
from src.classes.service.classes_version_expander import ClassesVersionExpander
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

_CLASS_NOT_FOUND_MSG = "Class not found"
_CLASS_DELETED_MSG = "Class has been deleted"
_CLASS_INACTIVE_MSG = "Class is not active"
_NOT_AN_OCCURRENCE_MSG = "Not a class occurrence on that date"
_CLASS_CANCELLED_MSG = "This class is cancelled that day"
_CLASS_FULL_MSG = "Class is full"


class SignupService:
    """Creates / removes a member's reservation for a class occurrence.

    Args:
        db_pool: Injected database connection pool.
        version_expander: The versioned recurrence + exception engine (pure),
            the same engine ``CheckinClassResolver`` uses to resolve an
            occurrence.
    """

    def __init__(
        self, db_pool: DirectDatabasePool, version_expander: ClassesVersionExpander
    ) -> None:
        self._db_pool = db_pool
        self._queries = CheckinQueries(db_pool)
        self._version_expander = version_expander

    async def create(
        self,
        member_id: UUID,
        gym_id: UUID,
        class_id: UUID,
        occurrence_date: date,
    ) -> SignupResponse:
        """Reserve ``member_id`` a spot on the occurrence.

        ``occurrence_date`` is the occurrence's ORIGINAL date.

        Raises:
            ValueError: "Class not found" if the class doesn't exist for the
                gym; "Class has been deleted" / "Class is not active" if the
                class is soft-deleted / inactive; "Not a class occurrence on
                that date" / "This class is cancelled that day" if
                ``occurrence_date`` isn't a real, non-cancelled occurrence of
                this class; "Class is full" if the occurrence is at its
                effective ``max_capacity`` and this member isn't already
                counted (signed up or attended).
        """
        class_row, occurrence = await self._validate_occurrence(
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
        return await self._insert(
            member_id, gym_id, class_id, occurrence_date, occurrence.original_time
        )

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
                            "original_date": occurrence_date,
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
    ) -> tuple[dict, EffectiveOccurrence]:
        """Load + validate the sign-up target.

        Loads the class row (exists / active / not soft-deleted for this
        gym), then resolves the occurrence against the class's schedule
        versions + exceptions to confirm a real, non-cancelled occurrence
        lands on ``occurrence_date``. Returns the class row (so the caller
        can read ``max_capacity`` / ``exception_max_capacity`` without a
        second read) and the resolved occurrence (for ``original_time``).

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

        occurrence = await self._resolve_occurrence(class_id, occurrence_date)
        if occurrence is None:
            raise ValueError(_NOT_AN_OCCURRENCE_MSG)
        if occurrence.is_cancelled:
            raise ValueError(_CLASS_CANCELLED_MSG)
        return class_row, occurrence

    async def _resolve_occurrence(
        self,
        class_id: UUID,
        occurrence_date: date,
    ) -> EffectiveOccurrence | None:
        """The occurrence whose ORIGINAL date is ``occurrence_date``,
        cancelled days INCLUDED (unlike ``CheckinClassResolver``'s default) so
        ``_validate_occurrence`` can distinguish a cancelled occurrence from a
        date that was never a recurrence at all and raise a more specific
        message for each. See ``CheckinClassResolver``'s module docstring for
        why the expand window is widened around a reschedule."""
        versions = await self._queries.get_schedule_versions(class_id)
        if not versions:
            return None

        window_start, window_end = await self._resolution_window(
            class_id, occurrence_date
        )
        instances = await self._queries.get_instance_exceptions(
            class_id, window_start, window_end
        )
        ranges = await self._queries.get_range_exceptions(
            class_id, window_start, window_end
        )
        occurrences = self._version_expander.expand(
            [to_expander_schedule(row) for row in versions],
            [to_expander_instance(row) for row in instances],
            [to_expander_range(row) for row in ranges],
            window_start,
            window_end,
            include_cancelled=True,
        )
        return next(
            (
                occ
                for occ in occurrences
                if occ.original_date == occurrence_date
            ),
            None,
        )

    async def _resolution_window(
        self, class_id: UUID, occurrence_date: date
    ) -> tuple[date, date]:
        """The window to expand: normally just ``occurrence_date``, widened
        to also cover a reschedule's ``new_date`` so the moved occurrence
        still resolves when addressed by its ORIGINAL date."""
        same_day = await self._queries.get_instance_exceptions(
            class_id, occurrence_date, occurrence_date
        )
        exception = same_day[0] if same_day else None
        if (
            exception is None
            or exception["is_cancelled"]
            or exception["new_date"] is None
        ):
            return occurrence_date, occurrence_date
        new_date = exception["new_date"]
        return min(occurrence_date, new_date), max(occurrence_date, new_date)

    # -- write -------------------------------------------------------------

    async def _insert(
        self,
        member_id: UUID,
        gym_id: UUID,
        class_id: UUID,
        occurrence_date: date,
        original_time: time,
    ) -> SignupResponse:
        """ON CONFLICT DO NOTHING create; falls back to a lookup on repeat.

        Both statements run in the same session/transaction, committed once.
        """
        insert_sql = load_sql(SQL_DIR / "signup_insert.sql")
        existing_sql = load_sql(SQL_DIR / "signup_load_existing.sql")
        existing_params = {
            "class_id": str(class_id),
            "member_id": str(member_id),
            "original_date": occurrence_date,
        }
        insert_params = {
            "gym_id": str(gym_id),
            "original_time": original_time,
            **existing_params,
        }

        async with self._db_pool.session() as session:
            row = (
                (await session.execute(text(insert_sql), insert_params))
                .mappings()
                .fetchone()
            )
            if row is not None:
                await session.commit()
                return SignupResponse(
                    signup_id=row["signup_id"], already_signed_up=False
                )

            existing = (
                (await session.execute(text(existing_sql), existing_params))
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
