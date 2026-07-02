"""Pure unit tests for the versioned schedule expander.

No DB, no Stripe, no clock — every case builds in-memory version rows and
asserts the exact owned occurrences. Coverage: ownership windowing (first
version owns back to -inf, last to +inf), the three mint-boundary cases
(already-ran stays on the old version; a not-yet-started slot follows the new
version; a new slot that already passed on mint day yields NO occurrence that
day), cross-version SLOT-level dedup (a boundary day CAN legitimately carry
BOTH versions' different-time occurrences — no day doubling; an exact-slot tie
is won by the earlier version), per-version frozen timezones, exceptions
binding to the owning version's slot, reschedule-from-a-past-original-slot
surviving a later version, owning schedule_id / original_start_at /
original_time tagging, past-render stability when new versions are appended,
cancelled-display ownership, and degenerate inputs.
"""

from collections.abc import Iterable, Mapping
from datetime import UTC, date, datetime, time
from uuid import UUID, uuid4

from schema.gym_class import RecurringUnit

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.classes.schema.classes_expander_schema import (
    ALL_DAYS_KEY,
    ClassSlot,
    ExpanderInstanceException,
    ExpanderScheduleVersion,
)
from src.classes.service.classes_expander import ClassesExpander
from src.classes.service.classes_version_expander import (
    ClassesVersionExpander,
)

CHICAGO = "America/Chicago"
DENVER = "America/Denver"
_DEFAULT_CREATED = datetime(2025, 1, 1, tzinfo=UTC)

# The shared scenario: a weekly Tuesday class. July 2025 Tuesdays are the
# 1st, 8th, 15th, 22nd and 29th; Chicago is CDT (UTC-5) all month.
JUL_TUESDAYS = (
    date(2025, 7, 1),
    date(2025, 7, 8),
    date(2025, 7, 15),
    date(2025, 7, 22),
    date(2025, 7, 29),
)
WINDOW = (date(2025, 6, 1), date(2025, 7, 31))


def _slot(t: time, instructor_id: UUID | None = None) -> ClassSlot:
    return ClassSlot(time=t, instructor_id=instructor_id)


def _version(
    *,
    class_id: UUID | None = None,
    effective_from: datetime,
    timezone: str = CHICAGO,
    class_time: time = time(18, 0),
    start_date: date = date(2025, 6, 1),
    end_date: date | None = None,
    recurring_unit: RecurringUnit = RecurringUnit.weekly,
    recurring_interval: int = 1,
    duration_minutes: int = 60,
    days: Iterable[str] = ("tue",),
    instructors: Mapping[str, UUID] | None = None,
) -> ExpanderScheduleVersion:
    """Build a single-slot-per-day schedule version — a weekly version puts
    ``class_time`` under each of ``days``; daily/monthly puts it under the
    reserved ``"all"`` key."""
    instructors = instructors or {}
    if recurring_unit == RecurringUnit.weekly:
        weekday_slots = {
            day: [_slot(class_time, instructors.get(day))] for day in days
        }
    else:
        weekday_slots = {
            ALL_DAYS_KEY: [_slot(class_time, instructors.get(ALL_DAYS_KEY))]
        }
    return ExpanderScheduleVersion(
        schedule_id=uuid4(),
        class_id=class_id or uuid4(),
        gym_id=uuid4(),
        effective_from=effective_from,
        timezone=timezone,
        duration_minutes=duration_minutes,
        recurring_unit=recurring_unit,
        recurring_interval=recurring_interval,
        weekday_slots=weekday_slots,
        start_date=start_date,
        end_date=end_date,
    )


def _instance(
    original_date: date,
    original_time: time = time(18, 0),
    *,
    is_cancelled: bool = False,
    new_class_time: time | None = None,
    new_date: date | None = None,
) -> ExpanderInstanceException:
    """Build a single-slot instance exception — ``original_time`` defaults to
    18:00, matching ``_version``'s default ``class_time``."""
    return ExpanderInstanceException(
        original_date=original_date,
        original_time=original_time,
        is_cancelled=is_cancelled,
        new_class_time=new_class_time,
        new_duration_minutes=None,
        new_instructor_id=None,
        new_date=new_date,
        created_at=_DEFAULT_CREATED,
    )


def _expander() -> ClassesVersionExpander:
    return ClassesVersionExpander(ClassesExpander())


def _by_original(occurrences: list) -> dict[date, object]:
    out = {}
    for occ in occurrences:
        assert occ.original_date not in out, "one-per-day invariant broken"
        out[occ.original_date] = occ
    return out


# -- single version -------------------------------------------------------


class TestSingleVersion:
    def test_first_version_owns_backdated_past(self) -> None:
        """v1's effective_from is only its mint stamp — a class created with
        a backdated start_date renders its whole past from version one."""
        v1 = _version(
            effective_from=datetime(2025, 6, 30, tzinfo=UTC),
        )
        occurrences = _expander().expand([v1], [], [], *WINDOW)
        # June Tuesdays (3, 10, 17, 24) precede effective_from yet render.
        assert [o.original_date for o in occurrences[:4]] == [
            date(2025, 6, 3),
            date(2025, 6, 10),
            date(2025, 6, 17),
            date(2025, 6, 24),
        ]
        assert len(occurrences) == 9  # 4 June + 5 July Tuesdays

    def test_tags_owner_and_original_slot(self) -> None:
        v1 = _version(effective_from=datetime(2025, 6, 1, tzinfo=UTC))
        occ = _expander().expand([v1], [], [], *WINDOW)[0]
        assert occ.schedule_id == v1.schedule_id
        assert occ.original_time == time(18, 0)
        # 18:00 CDT (UTC-5) == 23:00Z the same day.
        assert occ.original_start_at == datetime(
            2025, 6, 3, 23, 0, tzinfo=UTC
        )
        assert occ.original_start_at == occ.occurred_at

    def test_empty_versions_or_invalid_window(self) -> None:
        v1 = _version(effective_from=datetime(2025, 6, 1, tzinfo=UTC))
        assert _expander().expand([], [], [], *WINDOW) == []
        assert (
            _expander().expand(
                [v1], [], [], date(2025, 7, 2), date(2025, 7, 1)
            )
            == []
        )


# -- two versions: the mint boundary --------------------------------------


class TestMintBoundary:
    """A second version minted Tuesday 2025-07-08 at 14:00 Chicago (19:00Z)."""

    MINT = datetime(2025, 7, 8, 19, 0, tzinfo=UTC)

    def _pair(
        self, *, v2_time: time, v2_days: Iterable[str] = ("tue",)
    ) -> tuple[ExpanderScheduleVersion, ExpanderScheduleVersion]:
        class_id = uuid4()
        v1 = _version(
            class_id=class_id,
            effective_from=datetime(2025, 6, 1, tzinfo=UTC),
        )
        v2 = _version(
            class_id=class_id,
            effective_from=self.MINT,
            class_time=v2_time,
            days=v2_days,
        )
        return v1, v2

    def test_not_yet_started_slot_follows_new_version(self) -> None:
        """Boundary (ii): mint-day 18:00 hasn't started (>= mint instant), so
        the old version no longer produces it; the new 19:00 slot governs."""
        v1, v2 = self._pair(v2_time=time(19, 0))
        by_date = _by_original(_expander().expand([v1, v2], [], [], *WINDOW))
        mint_day = by_date[date(2025, 7, 8)]
        assert mint_day.schedule_id == v2.schedule_id
        assert mint_day.original_time == time(19, 0)
        # Later Tuesdays belong to v2; earlier ones to v1.
        assert by_date[date(2025, 7, 15)].schedule_id == v2.schedule_id
        assert by_date[date(2025, 7, 1)].schedule_id == v1.schedule_id

    def test_new_slot_already_passed_mint_day_has_no_occurrence(self) -> None:
        """Boundary (ii) variant: moving to noon at 2pm — v1 no longer owns
        18:00 (>= mint) and v2 can't own 12:00 (< mint) — no class that day."""
        v1, v2 = self._pair(v2_time=time(12, 0))
        by_date = _by_original(_expander().expand([v1, v2], [], [], *WINDOW))
        assert date(2025, 7, 8) not in by_date
        assert by_date[date(2025, 7, 15)].original_time == time(12, 0)

    def test_already_ran_stays_on_old_version_same_day_new_slot_also_renders(
        self,
    ) -> None:
        """Boundary (i): a 09:00 class already ran before the 2pm mint — v1
        keeps owning it. v2's same-day 20:00 candidate is a DIFFERENT SLOT
        (not yet run) — dedup is slot-level, not day-level, so it
        legitimately renders too (see TestSlotLevelDedup for the dedicated
        boundary-day coverage; the old model's "no day doubling" rule no
        longer applies once several slots per day are legal)."""
        class_id = uuid4()
        v1 = _version(
            class_id=class_id,
            effective_from=datetime(2025, 6, 1, tzinfo=UTC),
            class_time=time(9, 0),
        )
        v2 = _version(
            class_id=class_id,
            effective_from=self.MINT,
            class_time=time(20, 0),
        )
        occurrences = _expander().expand([v1, v2], [], [], *WINDOW)
        mint_day_occs = [
            occ for occ in occurrences if occ.original_date == date(2025, 7, 8)
        ]
        assert len(mint_day_occs) == 2
        by_time = {occ.original_time: occ for occ in mint_day_occs}
        assert by_time[time(9, 0)].schedule_id == v1.schedule_id
        assert by_time[time(20, 0)].schedule_id == v2.schedule_id
        by_date = _by_original(
            [occ for occ in occurrences if occ.original_date != date(2025, 7, 8)]
        )
        assert by_date[date(2025, 7, 1)].schedule_id == v1.schedule_id
        assert by_date[date(2025, 7, 15)].schedule_id == v2.schedule_id

    def test_removed_weekday_drops_future_keeps_past(self) -> None:
        """v2 moves the class to Thursdays: future Tuesdays vanish, past
        Tuesdays (owned by v1) keep rendering forever."""
        v1, v2 = self._pair(v2_time=time(18, 0), v2_days=("thu",))
        occurrences = _expander().expand([v1, v2], [], [], *WINDOW)
        by_date = _by_original(occurrences)
        # Past Tuesdays survive.
        assert date(2025, 7, 1) in by_date
        # Mint-day + later Tuesdays are gone; Thursdays appear from Jul 10.
        assert date(2025, 7, 8) not in by_date
        assert date(2025, 7, 22) not in by_date
        assert by_date[date(2025, 7, 10)].schedule_id == v2.schedule_id
        # Thursdays BEFORE the mint are not fabricated by v2.
        assert date(2025, 7, 3) not in by_date

    def test_past_render_is_stable_when_versions_are_appended(self) -> None:
        """Appending a third version never changes what the past renders."""
        v1, v2 = self._pair(v2_time=time(19, 0))
        before = _expander().expand(
            [v1, v2], [], [], date(2025, 6, 1), date(2025, 7, 8)
        )
        v3 = _version(
            class_id=v1.class_id,
            effective_from=datetime(2025, 7, 20, tzinfo=UTC),
            class_time=time(6, 0),
        )
        after = _expander().expand(
            [v1, v2, v3], [], [], date(2025, 6, 1), date(2025, 7, 8)
        )
        assert before == after


# -- slot-level dedup (not day-level) --------------------------------------


class TestSlotLevelDedup:
    """Dedup is at ``(original_date, original_time)``, not the date alone —
    a boundary day CAN legitimately show occurrences from both versions when
    they land at DIFFERENT times."""

    def test_boundary_day_shows_both_versions_at_different_times(
        self,
    ) -> None:
        """v1's Monday 06:00 already ran before a mint at Monday noon; v2's
        Monday 18:30 hasn't started yet — BOTH render on that same Monday,
        owned by their respective versions."""
        class_id = uuid4()
        mint = datetime(2025, 6, 2, 12, 0, tzinfo=UTC)  # a Monday, noon UTC
        v1 = _version(
            class_id=class_id,
            effective_from=datetime(2025, 1, 1, tzinfo=UTC),
            timezone="UTC",
            class_time=time(6, 0),
            days=("mon",),
            start_date=date(2025, 1, 1),
        )
        v2 = _version(
            class_id=class_id,
            effective_from=mint,
            timezone="UTC",
            class_time=time(18, 30),
            days=("mon",),
            start_date=date(2025, 1, 1),
        )
        boundary = date(2025, 6, 2)
        occurrences = _expander().expand(
            [v1, v2], [], [], boundary, boundary
        )

        assert len(occurrences) == 2
        by_time = {occ.original_time: occ for occ in occurrences}
        assert by_time[time(6, 0)].schedule_id == v1.schedule_id
        assert by_time[time(18, 30)].schedule_id == v2.schedule_id

    def test_earlier_version_wins_an_exact_slot_tie(self) -> None:
        """A tz shift can make the SAME wall-clock (date, time) slot eligible
        under BOTH versions' windowing at once (Chicago's 06:00 instant
        precedes the mint; Denver's 06:00 instant on the same wall date
        follows it, since Denver is an hour behind) — the claimed-slots
        dedup then keeps only the earlier version's occurrence."""
        class_id = uuid4()
        boundary_monday = date(2025, 6, 2)
        # Chicago 06:00 CDT -> 11:00 UTC; Denver 06:00 MDT -> 12:00 UTC.
        mint = datetime(2025, 6, 2, 11, 30, tzinfo=UTC)
        v1 = _version(
            class_id=class_id,
            effective_from=datetime(2025, 1, 1, tzinfo=UTC),
            timezone=CHICAGO,
            class_time=time(6, 0),
            days=("mon",),
            start_date=date(2025, 1, 1),
        )
        v2 = _version(
            class_id=class_id,
            effective_from=mint,
            timezone=DENVER,
            class_time=time(6, 0),
            days=("mon",),
            start_date=date(2025, 1, 1),
        )
        occurrences = _expander().expand(
            [v1, v2], [], [], boundary_monday, boundary_monday
        )

        assert len(occurrences) == 1
        assert occurrences[0].schedule_id == v1.schedule_id
        assert occurrences[0].occurred_at == datetime(
            2025, 6, 2, 11, 0, tzinfo=UTC
        )


# -- per-version frozen timezone ------------------------------------------


class TestFrozenTimezone:
    def test_each_version_expands_in_its_own_zone(self) -> None:
        """Same 18:00 wall clock, but v2 froze Denver — instants differ by
        the zone gap while the wall-clock slot stays 18:00."""
        class_id = uuid4()
        v1 = _version(
            class_id=class_id,
            effective_from=datetime(2025, 6, 1, tzinfo=UTC),
        )
        v2 = _version(
            class_id=class_id,
            effective_from=datetime(2025, 7, 8, 19, 0, tzinfo=UTC),
            timezone=DENVER,
        )
        by_date = _by_original(_expander().expand([v1, v2], [], [], *WINDOW))
        # v1: 18:00 CDT == 23:00Z. v2: 18:00 MDT == 00:00Z next day.
        assert by_date[date(2025, 7, 1)].occurred_at == datetime(
            2025, 7, 1, 23, 0, tzinfo=UTC
        )
        assert by_date[date(2025, 7, 15)].occurred_at == datetime(
            2025, 7, 16, 0, 0, tzinfo=UTC
        )
        assert by_date[date(2025, 7, 15)].original_time == time(18, 0)


# -- exceptions on a versioned schedule ------------------------------------


class TestExceptionsAcrossVersions:
    MINT = datetime(2025, 7, 8, 19, 0, tzinfo=UTC)

    def _pair(self) -> tuple[ExpanderScheduleVersion, ExpanderScheduleVersion]:
        class_id = uuid4()
        v1 = _version(
            class_id=class_id,
            effective_from=datetime(2025, 6, 1, tzinfo=UTC),
        )
        v2 = _version(
            class_id=class_id,
            effective_from=self.MINT,
            class_time=time(19, 0),
        )
        return v1, v2

    def test_exception_binds_to_owning_versions_slot(self) -> None:
        """A retime override on a v2-owned date: identity stays the v2 slot
        (original_time 19:00), the effective time is the override."""
        v1, v2 = self._pair()
        override = _instance(
            date(2025, 7, 15), time(19, 0), new_class_time=time(20, 0)
        )
        by_date = _by_original(
            _expander().expand([v1, v2], [override], [], *WINDOW)
        )
        occ = by_date[date(2025, 7, 15)]
        assert occ.schedule_id == v2.schedule_id
        assert occ.original_time == time(19, 0)
        assert occ.class_time == time(20, 0)
        # Ownership tested the ORIGINAL 19:00 slot, not the override.
        assert occ.original_start_at == datetime(
            2025, 7, 16, 0, 0, tzinfo=UTC
        )

    def test_reschedule_from_past_original_survives_newer_version(
        self,
    ) -> None:
        """An occurrence moved from a v1-owned original date to a date deep
        in v2's era stays owned by v1 (original instant < mint) — and v2's
        own occurrence that day still renders (effective-date doubling via
        reschedule is allowed; original dates never double)."""
        v1, v2 = self._pair()
        moved = _instance(
            date(2025, 7, 1), time(18, 0), new_date=date(2025, 7, 22)
        )
        occurrences = _expander().expand([v1, v2], [moved], [], *WINDOW)
        on_jul22 = [
            occ
            for occ in occurrences
            if occ.effective_date == date(2025, 7, 22)
        ]
        assert len(on_jul22) == 2
        moved_occ = next(o for o in on_jul22 if o.is_rescheduled)
        regular = next(o for o in on_jul22 if not o.is_rescheduled)
        assert moved_occ.schedule_id == v1.schedule_id
        assert moved_occ.original_date == date(2025, 7, 1)
        assert moved_occ.original_time == time(18, 0)
        assert regular.schedule_id == v2.schedule_id

    def test_cancelled_display_occurrence_still_claims_its_date(self) -> None:
        v1, v2 = self._pair()
        cancelled = _instance(date(2025, 7, 15), time(19, 0), is_cancelled=True)
        occurrences = _expander().expand(
            [v1, v2], [cancelled], [], *WINDOW, include_cancelled=True
        )
        by_date = _by_original(occurrences)
        occ = by_date[date(2025, 7, 15)]
        assert occ.is_cancelled is True
        assert occ.schedule_id == v2.schedule_id
        # The default expand drops it entirely.
        dropped = _by_original(
            _expander().expand([v1, v2], [cancelled], [], *WINDOW)
        )
        assert date(2025, 7, 15) not in dropped


# -- helper ----------------------------------------------------------------


class TestOriginalStartAt:
    def test_matches_ownership_arithmetic(self) -> None:
        v1 = _version(effective_from=datetime(2025, 6, 1, tzinfo=UTC))
        instant = _expander().original_start_at(v1, date(2025, 7, 1), time(18, 0))
        assert instant == datetime(2025, 7, 1, 23, 0, tzinfo=UTC)
