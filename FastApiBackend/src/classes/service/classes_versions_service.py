"""The schedule-version MINT engine — the one writer of gym_class_schedules.

Minting a version is the only way a class's recurring schedule changes, and it
always happens in ONE transaction with the version-change WIPE:

* A new version is effective NOW (server-stamped ``effective_from``; never
  future — no scheduled takeovers) and freezes the gym's current timezone.
* A submission deep-equal to the current version (all shape fields AND the
  timezone) is a no-op: no mint, no wipe.
* The wipe: every future-keyed row of the class — sign-ups, attendance (early
  check-ins), instance exceptions whose ORIGINAL slot instant is at/after the
  mint — is checked against the NEW version. A row SURVIVES iff the new
  version's recurrence still emits its ``original_date`` (with the new slot
  instant itself at/after the mint) AND the new ``class_time`` equals the
  row's ``original_time`` (exact wall-clock match). Non-survivors: sign-ups
  are DELETEd; attendance is reversed per member via the shared
  ``CheckinReverser`` (delete + points clawback floored at 0 + activity drop
  + pack auto-end reversal — billing-adjacent); instance exceptions are
  DELETEd (a dangling exception would zombie-apply if a later version
  reintroduced its date). Range exceptions are untouched — date-range
  semantics survive any schedule shape.
* Rows whose original slot already started before the mint are never touched
  — the old version owns them forever (the immutable past).

Consumers: class create (the FIRST version — no prior rows, no wipe), the
schedule half of a class update, the soft-delete wipe (no mint — a deleted
class produces no future slots, so NOTHING survives), and the gym
timezone-change re-mint (same shape + new tz per live class; wall-clock
matching keeps every row).

This service injects ``CheckinReverser`` — the same sanctioned
``classes -> checkin`` dependency ``ClassesUndoService`` uses, so the
per-member reversal has exactly one implementation. The reverser imports
nothing from ``src.classes``; no cycle.
"""

from datetime import UTC, date, datetime, time
from uuid import UUID
from zoneinfo import ZoneInfo

from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.checkin.service.checkin_reverser import CheckinReverser
from src.classes import SQL_DIR
from src.classes.schema.classes_crud_schema import GymClassScheduleFields
from src.classes.schema.classes_expander_schema import ExpanderScheduleVersion
from src.classes.service.classes_version_expander import (
    ClassesVersionExpander,
)
from src.shared.database import DirectDatabasePool
from src.shared.gym_timezone import get_gym_timezone
from src.shared.sql_loader import load_sql

_MINT_RACE_MSG = (
    "Another schedule edit for this class landed at the same instant; retry."
)

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
        reverser: CheckinReverser,
    ) -> None:
        self._db_pool = db_pool
        self._version_expander = version_expander
        self._reverser = reverser

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
                (the ``uq_class_schedule_version`` race; retry).
        """
        current = await self._current_version(session, class_id)
        if current is not None and self._shape_equal(
            shape, timezone, current
        ):
            return None

        effective_from = datetime.now(UTC)
        schedule_id = await self._insert_version(
            session, class_id, gym_id, shape, timezone, effective_from
        )
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
        early check-in reversed (points clawed back), every future instance
        exception dropped. Past rows are untouched (the past renders forever).
        Runs in the caller's OPEN transaction. A never-scheduled class (no
        versions) is a no-op.
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
        class. The wall-clock exact-slot match keeps every future-keyed row —
        same dates, same times — so nothing is wiped; the future simply
        renders in the new zone from the mint on, while every existing
        version keeps its own frozen zone (the past never moves).

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
                if await self.mint(
                    session, class_id, gym_id, shape, new_timezone
                ):
                    minted += 1
                await session.commit()
        return minted

    async def gym_timezone(self, session: AsyncSession, gym_id: UUID) -> str:
        """The gym's CURRENT IANA timezone — what a fresh mint freezes."""
        return await get_gym_timezone(session, gym_id)

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
        """Collect the class's future-keyed rows and wipe the non-survivors.

        A row is FUTURE-KEYED when its original slot instant — computed per
        row from ``original_date`` + its own ``original_time`` (exceptions,
        which store no time, use the OUTGOING version's ``class_time``) in
        the outgoing version's timezone — is at/after ``mint_instant``. A row
        whose slot already started (e.g. this morning's class, or anything
        past) is never collected. ``survives(day, slot_time) -> bool`` decides
        keep-vs-wipe per (date, wall-clock time) key.
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

        wiped_signup_dates: set[date] = set()
        for row in signup_rows:
            if not self._is_future_keyed(
                row["original_date"], row["original_time"], zone, mint_instant
            ):
                continue
            if not survives(row["original_date"], row["original_time"]):
                wiped_signup_dates.add(row["original_date"])
        for day in sorted(wiped_signup_dates):
            await self._delete_signups(session, class_id, day)

        doomed_attendance = [
            row
            for row in attendance_rows
            if self._is_future_keyed(
                row["original_date"], row["original_time"], zone, mint_instant
            )
            and not survives(row["original_date"], row["original_time"])
        ]
        if doomed_attendance:
            points_worth = await self._load_points(session, class_id)
            for row in doomed_attendance:
                await self._reverser.reverse(
                    session,
                    row["member_id"],
                    gym_id,
                    class_id,
                    row["original_date"],
                    points_worth,
                )

        for row in exception_rows:
            if not self._is_future_keyed(
                row["original_date"], outgoing_time, zone, mint_instant
            ):
                continue
            if not survives(row["original_date"], outgoing_time):
                await self._delete_exception(
                    session, class_id, row["original_date"]
                )

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

    # -- row plumbing ------------------------------------------------------

    async def _current_version(
        self, session: AsyncSession, class_id: UUID
    ) -> dict | None:
        """The class's latest version row (or None for a never-scheduled
        class — only possible mid-create)."""
        rows = await self._fetchall(
            session,
            "classes_schedules_for_class.sql",
            {"class_id": str(class_id)},
        )
        return rows[-1] if rows else None

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
            raise ValueError(_MINT_RACE_MSG) from exc
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

    async def _load_points(
        self, session: AsyncSession, class_id: UUID
    ) -> int:
        """The class's points_worth — the per-check-in award the wipe claws
        back, loaded once per wipe."""
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
        return int(row["points_worth"]) if row else 0

    async def _delete_signups(
        self, session: AsyncSession, class_id: UUID, day: date
    ) -> None:
        await session.execute(
            text(
                load_sql(
                    SQL_DIR / "classes_signups_delete_for_occurrence.sql"
                )
            ),
            {"class_id": str(class_id), "original_date": day},
        )

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
