"""The schedule-version MINT engine — the one writer of gym_class_schedules.

Minting a version is the only way a class's recurring schedule changes, and it
always happens in ONE transaction with the version-change WIPE:

* A new version is effective NOW (server-stamped ``effective_from``; never
  future — no scheduled takeovers) and freezes the gym's current timezone.
* A submission deep-equal to the current version (all shape fields AND the
  timezone) is a no-op: no mint, no wipe.
* **The WIPE decides per occurrence DATE.** A date is a wipe candidate when
  its ORIGINAL slot instant (the row's own ``original_time`` in the outgoing
  version's timezone; exceptions use the outgoing ``class_time``) is at/after
  the mint. A candidate is then LEFT ALONE when any of these hold:
    - the exception on it is a CANCELLATION — a cancellation is date-keyed
      intent ("this date is off"), so it survives any shape change; deleting
      it would silently revive the cancelled occurrence;
    - its EFFECTIVE start (the reschedule/retime target) is before the mint —
      the occurrence already ran; its attendance is real (points were
      legitimately earned) and the exception row is what anchors it;
    - the new version's recurrence still emits the date at the exact same
      wall-clock ``original_time`` (the exact-slot match — the row's
      identity survives untouched).
  Otherwise the date is torn down via the undo service's shared
  ``teardown_occurrence`` — attendance reversed per member through the one
  ``CheckinReverser`` implementation (points clawback floored at 0 + activity
  drop + pack auto-end reversal — billing-adjacent) and sign-ups deleted —
  and its (non-cancelled) instance exception is DELETEd. Range exceptions are
  never touched — date-range semantics survive any schedule shape. Rows whose
  original slot already started before the mint are never even candidates —
  the old version owns them forever (the immutable past).

Consumers: class create (the FIRST version — no prior rows, no wipe), the
schedule half of a class update, the soft-delete wipe (no mint — a deleted
class produces no future slots, so NOTHING survives), and the gym
timezone-change re-mint. The tz re-mint NEVER wipes: the shape is identical,
so every wall-clock slot survives by construction — running the instant-based
wipe would only produce false positives for slots inside the tz-delta window
around the re-mint moment. (Known narrow limitation of a tz change: a slot
whose instant falls between the new-tz and old-tz reading of the re-mint
moment sits in an ownership gap and may not render for that ONE day; its
rows are deliberately left untouched.)

This service depends on ``ClassesUndoService`` for the teardown, so the
billing-adjacent reversal + sign-up delete has exactly one implementation
across cancel, future-reschedule, and the wipe.
"""

from datetime import UTC, date, datetime, time
from uuid import UUID
from zoneinfo import ZoneInfo

from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.classes import SQL_DIR
from src.classes.schema.classes_crud_schema import GymClassScheduleFields
from src.classes.schema.classes_expander_schema import ExpanderScheduleVersion
from src.classes.service.classes_undo_service import ClassesUndoService
from src.classes.service.classes_version_expander import (
    ClassesVersionExpander,
)
from src.shared.database import DirectDatabasePool
from src.shared.gym_timezone import get_gym_timezone
from src.shared.sql_loader import load_sql

_MINT_RACE_MSG = (
    "Another schedule edit for this class landed at the same instant; retry."
)
_MINT_RACE_CONSTRAINT = "uq_class_schedule_version"

# The GymClassScheduleFields shape columns, compared one-by-one for the
# deep-equal no-op check (timezone is compared separately).
_SHAPE_FIELDS: tuple[str, ...] = tuple(
    GymClassScheduleFields.model_fields.keys()
)


class ClassesVersionsService:
    """Mints schedule versions and runs the version-change wipe."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        version_expander: ClassesVersionExpander,
        undo_service: ClassesUndoService,
    ) -> None:
        self._db_pool = db_pool
        self._version_expander = version_expander
        self._undo_service = undo_service

    # -- minting ----------------------------------------------------------

    async def mint(
        self,
        session: AsyncSession,
        class_id: UUID,
        gym_id: UUID,
        shape: GymClassScheduleFields,
        timezone: str,
    ) -> UUID | None:
        """Mint a new schedule version effective NOW, wiping future-keyed rows
        the new shape no longer produces — in the caller's OPEN transaction
        (no commit here).

        Returns the new ``schedule_id``, or None when the submission is
        deep-equal to the current version (no-op). The FIRST version of a
        class (no current) mints with no wipe — there are no rows yet.

        Raises:
            ValueError: two mints for the class landed on the same instant
                (the ``uq_class_schedule_version`` race; retry). Any other
                constraint violation (bad instructor / date range) propagates
                as ``IntegrityError`` for the caller's own mapping.
        """
        current = await self._current_version(session, class_id)
        minted = await self._mint_version(
            session, class_id, gym_id, shape, timezone, current
        )
        if minted is None:
            return None
        schedule_id, effective_from = minted
        if current is not None:
            new_version = self._as_expander_version(
                schedule_id, class_id, gym_id, shape, timezone, effective_from
            )
            await self._wipe(
                session,
                class_id,
                gym_id,
                outgoing_time=current["class_time"],
                outgoing_tz=current["timezone"],
                mint_instant=effective_from,
                survives=lambda day, slot: self._survives_new_version(
                    new_version, effective_from, day, slot
                ),
            )
        return schedule_id

    async def wipe_all_future(
        self,
        session: AsyncSession,
        class_id: UUID,
        gym_id: UUID,
    ) -> None:
        """The soft-delete wipe: a deleted class produces no future slots, so
        NO future-keyed row survives — every future sign-up is deleted, every
        early check-in reversed (points clawed back), every future
        (non-cancelled, not-yet-run) instance exception dropped. Rows of
        occurrences that already ran — by original slot OR by an effective
        (rescheduled) start in the past — are untouched (the past renders
        forever). Runs in the caller's OPEN transaction. A never-scheduled
        class (no versions) is a no-op.
        """
        current = await self._current_version(session, class_id)
        if current is None:
            return
        await self._wipe(
            session,
            class_id,
            gym_id,
            outgoing_time=current["class_time"],
            outgoing_tz=current["timezone"],
            mint_instant=datetime.now(UTC),
            survives=lambda day, slot: False,
        )

    async def remint_timezone(self, gym_id: UUID, new_timezone: str) -> int:
        """The gym timezone-change hook: mint a same-shape version (new tz)
        for every LIVE (non-deleted) class of the gym, one transaction per
        class. NO wipe runs — the shape is identical, so every wall-clock
        slot survives by construction, and the instant-based wipe would only
        false-positive on slots inside the tz-delta window around the
        re-mint moment. Every existing version keeps its own frozen zone
        (the past never moves); the future renders in the new zone from the
        re-mint on.

        Returns the number of classes re-minted (tz-identical classes are
        deep-equal no-ops and don't count).
        """
        classes = await self._live_class_ids(gym_id)
        minted = 0
        for class_id in classes:
            async with self._db_pool.session() as session:
                current = await self._current_version(session, class_id)
                if current is None:
                    continue
                shape = GymClassScheduleFields(
                    **{key: current[key] for key in _SHAPE_FIELDS}
                )
                if await self._mint_version(
                    session, class_id, gym_id, shape, new_timezone, current
                ):
                    minted += 1
                await session.commit()
        return minted

    async def gym_timezone(self, session: AsyncSession, gym_id: UUID) -> str:
        """The gym's CURRENT IANA timezone — what a fresh mint freezes."""
        return await get_gym_timezone(session, gym_id)

    async def _mint_version(
        self,
        session: AsyncSession,
        class_id: UUID,
        gym_id: UUID,
        shape: GymClassScheduleFields,
        timezone: str,
        current: dict | None,
    ) -> tuple[UUID, datetime] | None:
        """The deep-equal check + version INSERT (no wipe). Returns
        ``(schedule_id, effective_from)`` or None for a no-op."""
        if current is not None and self._shape_equal(
            shape, timezone, current
        ):
            return None
        effective_from = datetime.now(UTC)
        schedule_id = await self._insert_version(
            session, class_id, gym_id, shape, timezone, effective_from
        )
        return schedule_id, effective_from

    # -- the wipe ---------------------------------------------------------

    async def _wipe(
        self,
        session: AsyncSession,
        class_id: UUID,
        gym_id: UUID,
        outgoing_time: time,
        outgoing_tz: str,
        mint_instant: datetime,
        survives,
    ) -> None:
        """Collect the class's future-keyed occurrence dates and tear down
        the non-survivors (see the module docstring for the per-date rules).
        ``survives(day, slot_time) -> bool`` is the shape-specific keep test.
        """
        zone = ZoneInfo(outgoing_tz)
        floor_date = mint_instant.astimezone(zone).date()
        params = {"class_id": str(class_id), "floor_date": floor_date}

        signup_rows = await self._fetchall(
            session, "classes_wipe_collect_signups.sql", params
        )
        attendance_rows = await self._fetchall(
            session, "classes_wipe_collect_attendance.sql", params
        )
        exception_rows = await self._fetchall(
            session, "classes_wipe_collect_exceptions.sql", params
        )

        exceptions_by_date: dict[date, dict] = {
            row["original_date"]: row for row in exception_rows
        }
        # One original occurrence per gym-local date (the one-per-day
        # invariant), so any row's original_time is THE date's slot time;
        # exception-only dates fall back to the outgoing version's time.
        slot_times: dict[date, time] = {}
        for row in [*signup_rows, *attendance_rows]:
            slot_times.setdefault(row["original_date"], row["original_time"])

        candidate_dates = set(slot_times) | set(exceptions_by_date)
        for day in sorted(candidate_dates):
            slot_time = slot_times.get(day, outgoing_time)
            if not self._is_future_keyed(
                day, slot_time, zone, mint_instant
            ):
                continue  # original slot already started — immutable past
            exception_row = exceptions_by_date.get(day)
            if exception_row is not None and exception_row["is_cancelled"]:
                continue  # date-keyed intent: a cancellation never revives
            effective_start = self._effective_start(
                day, slot_time, exception_row, zone
            )
            if effective_start < mint_instant:
                continue  # rescheduled into the past — it already ran
            if survives(day, slot_time):
                continue
            await self._undo_service.teardown_occurrence(
                session, class_id, gym_id, day
            )
            if exception_row is not None:
                await self._delete_exception(session, class_id, day)

    def _survives_new_version(
        self,
        new_version: ExpanderScheduleVersion,
        mint_instant: datetime,
        day: date,
        slot_time: time,
    ) -> bool:
        """The mint survival rule: the NEW version's recurrence emits ``day``
        (owned — its slot instant at/after the mint) AND the new
        ``class_time`` equals the row's wall-clock slot (exact match)."""
        if slot_time != new_version.class_time:
            return False
        occurrences = self._version_expander.expand(
            [new_version], [], [], day, day
        )
        return any(
            occ.original_date == day
            and occ.original_start_at is not None
            and occ.original_start_at >= mint_instant
            for occ in occurrences
        )

    @staticmethod
    def _is_future_keyed(
        day: date,
        slot_time: time,
        zone: ZoneInfo,
        mint_instant: datetime,
    ) -> bool:
        """Whether the (date, wall-clock time) slot starts at/after the mint."""
        slot_instant = datetime.combine(
            day, slot_time, tzinfo=zone
        ).astimezone(UTC)
        return slot_instant >= mint_instant

    @staticmethod
    def _effective_start(
        day: date,
        slot_time: time,
        exception_row: dict | None,
        zone: ZoneInfo,
    ) -> datetime:
        """The occurrence's EFFECTIVE start instant — the reschedule/retime
        target when an exception moves it, else the original slot."""
        if exception_row is None:
            effective_day, effective_time = day, slot_time
        else:
            effective_day = exception_row["new_date"] or day
            effective_time = exception_row["new_class_time"] or slot_time
        return datetime.combine(
            effective_day, effective_time, tzinfo=zone
        ).astimezone(UTC)

    # -- row plumbing ------------------------------------------------------

    async def _current_version(
        self, session: AsyncSession, class_id: UUID
    ) -> dict | None:
        """The class's latest version row via the one-row
        ``gym_class_schedules_current`` view read (or None for a
        never-scheduled class — only possible mid-create)."""
        row = (
            (
                await session.execute(
                    text(load_sql(SQL_DIR / "classes_schedule_current.sql")),
                    {"class_id": str(class_id)},
                )
            )
            .mappings()
            .fetchone()
        )
        return dict(row) if row else None

    async def _insert_version(
        self,
        session: AsyncSession,
        class_id: UUID,
        gym_id: UUID,
        shape: GymClassScheduleFields,
        timezone: str,
        effective_from: datetime,
    ) -> UUID:
        params: dict = {
            "class_id": str(class_id),
            "gym_id": str(gym_id),
            "effective_from": effective_from,
            "timezone": timezone,
        }
        for field in _SHAPE_FIELDS:
            value = getattr(shape, field)
            if isinstance(value, UUID):
                value = str(value)
            elif field == "recurring_unit":
                value = value.value
            params[field] = value
        try:
            row = (
                (
                    await session.execute(
                        text(
                            load_sql(SQL_DIR / "classes_schedule_insert.sql")
                        ),
                        params,
                    )
                )
                .mappings()
                .fetchone()
            )
        except IntegrityError as exc:
            # Only the same-instant mint race becomes the retry message;
            # FK / CHECK violations (bad instructor, end_date < start_date)
            # propagate so the caller maps them to its own 400.
            if _MINT_RACE_CONSTRAINT in str(exc.orig):
                raise ValueError(_MINT_RACE_MSG) from exc
            raise
        if not row:
            raise RuntimeError("Version INSERT did not return a row")
        return row["schedule_id"]

    @staticmethod
    def _as_expander_version(
        schedule_id: UUID,
        class_id: UUID,
        gym_id: UUID,
        shape: GymClassScheduleFields,
        timezone: str,
        effective_from: datetime,
    ) -> ExpanderScheduleVersion:
        return ExpanderScheduleVersion(
            schedule_id=schedule_id,
            class_id=class_id,
            gym_id=gym_id,
            effective_from=effective_from,
            timezone=timezone,
            **{
                field: getattr(shape, field) for field in _SHAPE_FIELDS
            },
        )

    @staticmethod
    def _shape_equal(
        shape: GymClassScheduleFields,
        timezone: str,
        current: dict,
    ) -> bool:
        """Deep-equal: every shape field AND the frozen timezone match the
        current version. A tz-only change is NOT equal (a real re-mint)."""
        if timezone != current["timezone"]:
            return False
        for field in _SHAPE_FIELDS:
            submitted = getattr(shape, field)
            existing = current[field]
            if field == "recurring_unit":
                submitted = submitted.value
                existing = (
                    existing if isinstance(existing, str) else str(existing)
                )
            if isinstance(submitted, UUID) or isinstance(existing, UUID):
                submitted = (
                    str(submitted) if submitted is not None else None
                )
                existing = str(existing) if existing is not None else None
            if submitted != existing:
                return False
        return True

    async def _live_class_ids(self, gym_id: UUID) -> list[UUID]:
        """The gym's non-deleted class ids (the tz re-mint targets)."""
        async with self._db_pool.session() as session:
            rows = await self._fetchall(
                session, "classes_board_classes.sql", {"gym_id": str(gym_id)}
            )
        return [
            row["class_id"] for row in rows if not row["is_deleted"]
        ]

    async def _delete_exception(
        self, session: AsyncSession, class_id: UUID, day: date
    ) -> None:
        await session.execute(
            text(load_sql(SQL_DIR / "classes_wipe_delete_exception.sql")),
            {"class_id": str(class_id), "original_date": day},
        )

    @staticmethod
    async def _fetchall(
        session: AsyncSession, sql_file: str, params: dict
    ) -> list[dict]:
        rows = (
            (
                await session.execute(
                    text(load_sql(SQL_DIR / sql_file)), params
                )
            )
            .mappings()
            .all()
        )
        return [dict(row) for row in rows]
