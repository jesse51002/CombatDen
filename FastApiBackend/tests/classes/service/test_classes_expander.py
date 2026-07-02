"""Pure unit tests for the class recurrence + exception expander.

No DB, no Stripe, no clock — every case is built from in-memory contracts and
asserts the exact effective occurrences. Coverage: daily (interval 1 and 3,
plus mid-stream window anchoring), weekly (multi-day interval 1 and bi-weekly
interval 2), monthly last-day clamp, end_date clamp, instance cancel / reschedule
(target in-window and out-of-window, original suppressed either way), range
cancel / instructor override, instance-wins-over-range on the same date,
earliest-created range tie-break, DST spring-forward for America/Chicago
(boundary crossing + the nonexistent gap time), degenerate / no-overlap
windows, MULTI-SLOT-PER-DAY fan-out (weekly two slots + daily/monthly "all"
fan-out), per-slot exception binding (a same-day sibling slot is untouched),
range cancel covering every slot of a date, ``instructor_for`` per slot, and
the ``weekday_slots`` canonicalizer's validation rules.
"""

from collections.abc import Iterable, Mapping
from datetime import UTC, date, datetime, time
from uuid import UUID, uuid4

import pytest
from schema.gym_class import RecurringUnit

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.classes.schema.classes_expander_schema import (
    ALL_DAYS_KEY,
    ClassSlot,
    ExpanderClass,
    ExpanderInstanceException,
    ExpanderRangeException,
    canonicalize_weekday_slots,
)
from src.classes.service.classes_expander import ClassesExpander

UTC_TZ = "UTC"
CHICAGO = "America/Chicago"
_DEFAULT_CREATED = datetime(2025, 1, 1, tzinfo=UTC)


def _slot(t: time, instructor_id: UUID | None = None) -> ClassSlot:
    return ClassSlot(time=t, instructor_id=instructor_id)


def _class(
    *,
    recurring_unit: RecurringUnit,
    start_date: date,
    recurring_interval: int = 1,
    end_date: date | None = None,
    class_time: time = time(9, 0),
    duration_minutes: int = 60,
    days: Iterable[str] = (),
    instructors: Mapping[str, UUID] | None = None,
) -> ExpanderClass:
    """Build a single-slot-per-day ExpanderClass — most cases here need only
    one slot per day. A weekly class puts ``class_time`` under each of
    ``days`` (``instructors[day]`` is that day's instructor); daily/monthly
    puts the single slot under the reserved ``"all"`` key
    (``instructors[ALL_DAYS_KEY]`` is its instructor)."""
    instructors = instructors or {}
    if recurring_unit == RecurringUnit.weekly:
        weekday_slots = {
            day: [_slot(class_time, instructors.get(day))] for day in days
        }
    else:
        weekday_slots = {
            ALL_DAYS_KEY: [_slot(class_time, instructors.get(ALL_DAYS_KEY))]
        }
    return ExpanderClass(
        class_id=uuid4(),
        gym_id=uuid4(),
        duration_minutes=duration_minutes,
        recurring_unit=recurring_unit,
        recurring_interval=recurring_interval,
        weekday_slots=weekday_slots,
        start_date=start_date,
        end_date=end_date,
    )


def _class_with_slots(
    *,
    recurring_unit: RecurringUnit,
    start_date: date,
    weekday_slots: dict[str, list[ClassSlot]],
    recurring_interval: int = 1,
    end_date: date | None = None,
    duration_minutes: int = 60,
) -> ExpanderClass:
    """Build an ExpanderClass from a caller-supplied full ``weekday_slots``
    shape — for the multi-slot-per-day cases a single ``class_time`` can't
    express."""
    return ExpanderClass(
        class_id=uuid4(),
        gym_id=uuid4(),
        duration_minutes=duration_minutes,
        recurring_unit=recurring_unit,
        recurring_interval=recurring_interval,
        weekday_slots=weekday_slots,
        start_date=start_date,
        end_date=end_date,
    )


def _instance(
    original_date: date,
    original_time: time = time(9, 0),
    *,
    is_cancelled: bool = False,
    new_class_time: time | None = None,
    new_duration_minutes: int | None = None,
    new_instructor_id: UUID | None = None,
    new_date: date | None = None,
    created_at: datetime = _DEFAULT_CREATED,
) -> ExpanderInstanceException:
    """Build a single-slot instance exception — ``original_time`` defaults to
    9:00, matching ``_class``'s default ``class_time``."""
    return ExpanderInstanceException(
        original_date=original_date,
        original_time=original_time,
        is_cancelled=is_cancelled,
        new_class_time=new_class_time,
        new_duration_minutes=new_duration_minutes,
        new_instructor_id=new_instructor_id,
        new_date=new_date,
        created_at=created_at,
    )


def _range(
    start_date: date,
    end_date: date,
    *,
    is_cancelled: bool = False,
    new_instructor_id: UUID | None = None,
    created_at: datetime = _DEFAULT_CREATED,
    exception_id: UUID | None = None,
) -> ExpanderRangeException:
    """Build a date-range exception."""
    return ExpanderRangeException(
        exception_id=exception_id or uuid4(),
        start_date=start_date,
        end_date=end_date,
        is_cancelled=is_cancelled,
        new_instructor_id=new_instructor_id,
        created_at=created_at,
    )


def _dates(year: int, month: int, days: Iterable[int]) -> list[date]:
    """Helper: list of dates in one month from day numbers."""
    return [date(year, month, day) for day in days]


def _effective(occurrences: list) -> list[date]:
    return [occ.effective_date for occ in occurrences]


# -- daily ---------------------------------------------------------------


def test_daily_interval_one() -> None:
    exp = ClassesExpander()
    cls = _class(recurring_unit=RecurringUnit.daily, start_date=date(2025, 1, 1))

    occ = exp.expand(cls, [], [], date(2025, 1, 1), date(2025, 1, 5), UTC_TZ)

    assert _effective(occ) == _dates(2025, 1, [1, 2, 3, 4, 5])
    assert all(o.original_date == o.effective_date for o in occ)
    assert all(not o.is_rescheduled for o in occ)
    # occurred_at is tz-aware UTC; for a UTC gym it equals the local combine.
    assert occ[0].occurred_at == datetime(2025, 1, 1, 9, 0, tzinfo=UTC)
    assert occ[0].occurred_at.tzinfo is not None


def test_daily_interval_three_anchored_to_start_date() -> None:
    exp = ClassesExpander()
    cls = _class(
        recurring_unit=RecurringUnit.daily,
        recurring_interval=3,
        start_date=date(2025, 1, 1),
    )

    occ = exp.expand(cls, [], [], date(2025, 1, 1), date(2025, 1, 10), UTC_TZ)
    assert _effective(occ) == _dates(2025, 1, [1, 4, 7, 10])

    # A window that starts mid-stream still counts the interval from
    # start_date, not from window_start.
    occ2 = exp.expand(cls, [], [], date(2025, 1, 5), date(2025, 1, 10), UTC_TZ)
    assert _effective(occ2) == _dates(2025, 1, [7, 10])


# -- weekly --------------------------------------------------------------


def test_weekly_interval_one_multi_day() -> None:
    exp = ClassesExpander()
    mon_iid = uuid4()
    # 2025-01-06 is a Monday.
    cls = _class(
        recurring_unit=RecurringUnit.weekly,
        start_date=date(2025, 1, 6),
        days=("mon", "wed", "fri"),
        instructors={"mon": mon_iid},
    )

    occ = exp.expand(cls, [], [], date(2025, 1, 6), date(2025, 1, 19), UTC_TZ)

    assert _effective(occ) == _dates(2025, 1, [6, 8, 10, 13, 15, 17])
    by_date = {o.effective_date: o.instructor_id for o in occ}
    assert by_date[date(2025, 1, 6)] == mon_iid  # Monday slot has an instructor
    assert by_date[date(2025, 1, 8)] is None  # Wednesday slot has none


def test_weekly_interval_two_biweekly() -> None:
    exp = ClassesExpander()
    cls = _class(
        recurring_unit=RecurringUnit.weekly,
        recurring_interval=2,
        start_date=date(2025, 1, 6),
        days=("mon",),
    )

    occ = exp.expand(cls, [], [], date(2025, 1, 6), date(2025, 2, 10), UTC_TZ)

    assert _effective(occ) == [date(2025, 1, 6), date(2025, 1, 20), date(2025, 2, 3)]


# -- monthly -------------------------------------------------------------


def test_monthly_last_day_clamp() -> None:
    exp = ClassesExpander()
    cls = _class(recurring_unit=RecurringUnit.monthly, start_date=date(2025, 1, 31))

    occ = exp.expand(cls, [], [], date(2025, 1, 31), date(2025, 4, 30), UTC_TZ)

    # Jan31 -> Feb28 (clamped) -> Mar31 (recomputed from start.day, NOT chained
    # off the Feb clamp) -> Apr30 (clamped).
    assert _effective(occ) == [
        date(2025, 1, 31),
        date(2025, 2, 28),
        date(2025, 3, 31),
        date(2025, 4, 30),
    ]


def test_monthly_window_lower_bound_skips_early_anchors() -> None:
    exp = ClassesExpander()
    cls = _class(recurring_unit=RecurringUnit.monthly, start_date=date(2025, 1, 31))

    occ = exp.expand(cls, [], [], date(2025, 2, 1), date(2025, 4, 30), UTC_TZ)

    assert _effective(occ) == [
        date(2025, 2, 28),
        date(2025, 3, 31),
        date(2025, 4, 30),
    ]


# -- end_date bound ------------------------------------------------------


def test_end_date_clamps_occurrences() -> None:
    exp = ClassesExpander()
    cls = _class(
        recurring_unit=RecurringUnit.daily,
        start_date=date(2025, 1, 1),
        end_date=date(2025, 1, 3),
    )

    occ = exp.expand(cls, [], [], date(2025, 1, 1), date(2025, 1, 10), UTC_TZ)

    assert _effective(occ) == _dates(2025, 1, [1, 2, 3])


# -- instance exceptions -------------------------------------------------


def test_instance_cancel_drops_the_date() -> None:
    exp = ClassesExpander()
    cls = _class(recurring_unit=RecurringUnit.daily, start_date=date(2025, 1, 1))
    inst = _instance(date(2025, 1, 3), is_cancelled=True)

    occ = exp.expand(cls, [inst], [], date(2025, 1, 1), date(2025, 1, 5), UTC_TZ)

    assert _effective(occ) == _dates(2025, 1, [1, 2, 4, 5])


def test_instance_reschedule_in_window() -> None:
    exp = ClassesExpander()
    new_iid = uuid4()
    cls = _class(
        recurring_unit=RecurringUnit.weekly,
        start_date=date(2025, 1, 6),
        days=("mon",),
        class_time=time(9, 0),
        duration_minutes=60,
    )
    # Move the Jan 13 Monday to Wed Jan 15 (a non-class day) with overrides.
    inst = _instance(
        date(2025, 1, 13),
        new_date=date(2025, 1, 15),
        new_class_time=time(18, 0),
        new_duration_minutes=90,
        new_instructor_id=new_iid,
    )

    occ = exp.expand(cls, [inst], [], date(2025, 1, 6), date(2025, 1, 31), UTC_TZ)

    # Sorted by occurred_at, so the moved Jan 15 lands in date order.
    assert _effective(occ) == _dates(2025, 1, [6, 15, 20, 27])
    moved = occ[1]
    assert moved.original_date == date(2025, 1, 13)
    assert moved.is_rescheduled is True
    assert moved.class_time == time(18, 0)
    assert moved.duration_minutes == 90
    assert moved.instructor_id == new_iid
    # The original Jan 13 date is suppressed.
    assert date(2025, 1, 13) not in _effective(occ)


def test_instance_reschedule_out_of_window_suppresses_original() -> None:
    exp = ClassesExpander()
    cls = _class(
        recurring_unit=RecurringUnit.weekly,
        start_date=date(2025, 1, 6),
        days=("mon",),
    )
    inst = _instance(date(2025, 1, 13), new_date=date(2025, 2, 1))

    occ = exp.expand(cls, [inst], [], date(2025, 1, 6), date(2025, 1, 20), UTC_TZ)

    # Jan 13 moved to Feb 1 (outside window): dropped here, original still gone.
    assert _effective(occ) == [date(2025, 1, 6), date(2025, 1, 20)]


def test_instance_override_zero_values_are_not_treated_as_absent() -> None:
    exp = ClassesExpander()
    cls = _class(
        recurring_unit=RecurringUnit.daily,
        start_date=date(2025, 1, 1),
        class_time=time(9, 0),
    )
    # midnight (time(0,0)) is a real override, not "absent".
    inst = _instance(date(2025, 1, 2), new_class_time=time(0, 0))

    occ = exp.expand(cls, [inst], [], date(2025, 1, 1), date(2025, 1, 2), UTC_TZ)

    jan2 = next(o for o in occ if o.effective_date == date(2025, 1, 2))
    assert jan2.class_time == time(0, 0)


# -- range exceptions ----------------------------------------------------


def test_range_cancel_drops_covered_dates() -> None:
    exp = ClassesExpander()
    cls = _class(recurring_unit=RecurringUnit.daily, start_date=date(2025, 1, 1))
    rng = _range(date(2025, 1, 4), date(2025, 1, 6), is_cancelled=True)

    occ = exp.expand(cls, [], [rng], date(2025, 1, 1), date(2025, 1, 10), UTC_TZ)

    assert _effective(occ) == _dates(2025, 1, [1, 2, 3, 7, 8, 9, 10])


def test_range_instructor_override() -> None:
    exp = ClassesExpander()
    base_iid = uuid4()
    sub_iid = uuid4()
    cls = _class(
        recurring_unit=RecurringUnit.daily,
        start_date=date(2025, 1, 1),
        instructors={ALL_DAYS_KEY: base_iid},
    )
    rng = _range(date(2025, 1, 4), date(2025, 1, 6), new_instructor_id=sub_iid)

    occ = exp.expand(cls, [], [rng], date(2025, 1, 1), date(2025, 1, 7), UTC_TZ)

    by_date = {o.effective_date: o.instructor_id for o in occ}
    assert by_date[date(2025, 1, 3)] == base_iid
    assert by_date[date(2025, 1, 4)] == sub_iid
    assert by_date[date(2025, 1, 5)] == sub_iid
    assert by_date[date(2025, 1, 6)] == sub_iid
    assert by_date[date(2025, 1, 7)] == base_iid


def test_instance_exception_wins_over_range_on_same_date() -> None:
    exp = ClassesExpander()
    cls = _class(
        recurring_unit=RecurringUnit.daily,
        start_date=date(2025, 1, 1),
        class_time=time(9, 0),
    )
    rng = _range(date(2025, 1, 4), date(2025, 1, 6), is_cancelled=True)
    inst = _instance(date(2025, 1, 5), new_class_time=time(20, 0))

    occ = exp.expand(cls, [inst], [rng], date(2025, 1, 1), date(2025, 1, 10), UTC_TZ)

    # Jan 4 and Jan 6 cancelled by the range; Jan 5 survives via the instance.
    assert _effective(occ) == _dates(2025, 1, [1, 2, 3, 5, 7, 8, 9, 10])
    jan5 = next(o for o in occ if o.effective_date == date(2025, 1, 5))
    assert jan5.class_time == time(20, 0)
    assert jan5.is_rescheduled is False


def test_earliest_created_range_wins_on_overlap() -> None:
    exp = ClassesExpander()
    sub_iid = uuid4()
    cls = _class(recurring_unit=RecurringUnit.daily, start_date=date(2025, 1, 4))
    early = _range(
        date(2025, 1, 4),
        date(2025, 1, 4),
        new_instructor_id=sub_iid,
        created_at=datetime(2025, 1, 1, tzinfo=UTC),
    )
    late = _range(
        date(2025, 1, 4),
        date(2025, 1, 4),
        is_cancelled=True,
        created_at=datetime(2025, 1, 2, tzinfo=UTC),
    )

    # Pass them out of creation order; the expander sorts by created_at.
    occ = exp.expand(cls, [], [late, early], date(2025, 1, 4), date(2025, 1, 4), UTC_TZ)

    assert len(occ) == 1
    assert occ[0].instructor_id == sub_iid  # earliest-created, not cancelled


# -- include_cancelled (display mode) ------------------------------------


def test_include_cancelled_shows_cancelled_instance() -> None:
    exp = ClassesExpander()
    sub_iid = uuid4()
    cls = _class(
        recurring_unit=RecurringUnit.daily,
        start_date=date(2025, 1, 1),
        class_time=time(9, 0),
        duration_minutes=60,
        instructors={ALL_DAYS_KEY: sub_iid},
    )
    # An instance cancel that also carries (now irrelevant) overrides.
    inst = _instance(
        date(2025, 1, 3),
        is_cancelled=True,
        new_class_time=time(20, 0),
        new_duration_minutes=15,
        new_instructor_id=uuid4(),
    )

    # Default mode drops Jan 3 entirely.
    dropped = exp.expand(
        cls, [inst], [], date(2025, 1, 1), date(2025, 1, 5), UTC_TZ
    )
    assert _effective(dropped) == _dates(2025, 1, [1, 2, 4, 5])
    assert all(not o.is_cancelled for o in dropped)

    # include_cancelled keeps Jan 3, flagged, on its original date with the
    # class defaults (NOT the cancelled instance's overrides).
    shown = exp.expand(
        cls,
        [inst],
        [],
        date(2025, 1, 1),
        date(2025, 1, 5),
        UTC_TZ,
        include_cancelled=True,
    )
    assert _effective(shown) == _dates(2025, 1, [1, 2, 3, 4, 5])
    jan3 = next(o for o in shown if o.effective_date == date(2025, 1, 3))
    assert jan3.is_cancelled is True
    assert jan3.original_date == date(2025, 1, 3)
    assert jan3.is_rescheduled is False
    assert jan3.class_time == time(9, 0)  # class default, not the 20:00 override
    assert jan3.duration_minutes == 60  # class default, not the 15 override
    assert jan3.instructor_id == sub_iid  # weekday default, not the override
    assert all(not o.is_cancelled for o in shown if o.effective_date != date(2025, 1, 3))
    # An INSTANCE cancel never sets cancelling_range_id -- only a RANGE cancel
    # does (see test_include_cancelled_shows_cancelled_range).
    assert jan3.cancelling_range_id is None
    assert all(o.cancelling_range_id is None for o in shown)


def test_include_cancelled_shows_cancelled_range() -> None:
    exp = ClassesExpander()
    cls = _class(
        recurring_unit=RecurringUnit.daily,
        start_date=date(2025, 1, 1),
        class_time=time(9, 0),
    )
    rng = _range(date(2025, 1, 4), date(2025, 1, 6), is_cancelled=True)

    # Default mode drops the whole covered range.
    dropped = exp.expand(
        cls, [], [rng], date(2025, 1, 1), date(2025, 1, 7), UTC_TZ
    )
    assert _effective(dropped) == _dates(2025, 1, [1, 2, 3, 7])

    # include_cancelled keeps the covered dates, all flagged.
    shown = exp.expand(
        cls,
        [],
        [rng],
        date(2025, 1, 1),
        date(2025, 1, 7),
        UTC_TZ,
        include_cancelled=True,
    )
    assert _effective(shown) == _dates(2025, 1, [1, 2, 3, 4, 5, 6, 7])
    cancelled = {o.effective_date for o in shown if o.is_cancelled}
    assert cancelled == set(_dates(2025, 1, [4, 5, 6]))
    # A RANGE cancel threads the cancelling range's own id onto every
    # occurrence it cancels; everything else stays None.
    for occ in shown:
        expected = rng.exception_id if occ.is_cancelled else None
        assert occ.cancelling_range_id == expected


def test_cancelling_range_id_is_the_earliest_created_covering_range() -> None:
    """When several ranges overlap, the id threaded onto a cancelled
    occurrence is the same earliest-created range that actually governs it
    (mirrors test_earliest_created_range_wins_on_overlap)."""
    exp = ClassesExpander()
    cls = _class(recurring_unit=RecurringUnit.daily, start_date=date(2025, 1, 4))
    early_cancel = _range(
        date(2025, 1, 4),
        date(2025, 1, 4),
        is_cancelled=True,
        created_at=datetime(2025, 1, 1, tzinfo=UTC),
    )
    late_cancel = _range(
        date(2025, 1, 4),
        date(2025, 1, 4),
        is_cancelled=True,
        created_at=datetime(2025, 1, 2, tzinfo=UTC),
    )

    occ = exp.expand(
        cls,
        [],
        [late_cancel, early_cancel],
        date(2025, 1, 4),
        date(2025, 1, 4),
        UTC_TZ,
        include_cancelled=True,
    )

    assert len(occ) == 1
    assert occ[0].is_cancelled is True
    assert occ[0].cancelling_range_id == early_cancel.exception_id


# -- timezone / DST ------------------------------------------------------


def test_dst_spring_forward_boundary_chicago() -> None:
    exp = ClassesExpander()
    # 2025-03-09 is the US spring-forward day (02:00 CST -> 03:00 CDT).
    cls = _class(
        recurring_unit=RecurringUnit.daily,
        start_date=date(2025, 3, 8),
        class_time=time(18, 0),
    )

    occ = exp.expand(cls, [], [], date(2025, 3, 8), date(2025, 3, 9), CHICAGO)

    # Mar 8 is CST (UTC-6): 18:00 -> 00:00 UTC next day.
    assert occ[0].occurred_at == datetime(2025, 3, 9, 0, 0, tzinfo=UTC)
    # Mar 9 is CDT (UTC-5): 18:00 -> 23:00 UTC same day.
    assert occ[1].occurred_at == datetime(2025, 3, 9, 23, 0, tzinfo=UTC)


def test_dst_spring_forward_gap_time_accepted_as_is() -> None:
    exp = ClassesExpander()
    # 02:30 on the spring-forward day is a wall time that never existed.
    cls = _class(
        recurring_unit=RecurringUnit.daily,
        start_date=date(2025, 3, 9),
        class_time=time(2, 30),
    )

    occ = exp.expand(cls, [], [], date(2025, 3, 9), date(2025, 3, 9), CHICAGO)

    # Default fold=0 resolves the gap with the pre-transition CST offset.
    assert occ[0].occurred_at == datetime(2025, 3, 9, 8, 30, tzinfo=UTC)


# -- degenerate / no-overlap windows -------------------------------------


def test_invalid_window_returns_empty() -> None:
    exp = ClassesExpander()
    cls = _class(recurring_unit=RecurringUnit.daily, start_date=date(2025, 1, 1))

    assert exp.expand(cls, [], [], date(2025, 1, 10), date(2025, 1, 1), UTC_TZ) == []


def test_no_overlap_returns_empty() -> None:
    exp = ClassesExpander()
    # Class starts after the window.
    future = _class(recurring_unit=RecurringUnit.daily, start_date=date(2025, 6, 1))
    assert exp.expand(future, [], [], date(2025, 1, 1), date(2025, 1, 31), UTC_TZ) == []

    # Class ended before the window.
    ended = _class(
        recurring_unit=RecurringUnit.daily,
        start_date=date(2025, 1, 1),
        end_date=date(2025, 1, 5),
    )
    assert exp.expand(ended, [], [], date(2025, 2, 1), date(2025, 2, 28), UTC_TZ) == []


# -- multi-slot-per-day fan-out -------------------------------------------


def test_weekly_two_slots_same_day_two_occurrences() -> None:
    """A weekly day with two slots fans out to two occurrences on the SAME
    date, each carrying its own distinct original_time / occurred_at."""
    exp = ClassesExpander()
    cls = _class_with_slots(
        recurring_unit=RecurringUnit.weekly,
        start_date=date(2025, 1, 6),  # a Monday
        weekday_slots={"mon": [_slot(time(6, 0)), _slot(time(18, 0))]},
    )

    occ = exp.expand(cls, [], [], date(2025, 1, 6), date(2025, 1, 6), UTC_TZ)

    assert len(occ) == 2
    assert {o.effective_date for o in occ} == {date(2025, 1, 6)}
    times = sorted(o.original_time for o in occ)
    assert times == [time(6, 0), time(18, 0)]
    occurred_ats = {o.occurred_at for o in occ}
    assert len(occurred_ats) == 2  # distinct instants


def test_daily_all_key_fans_out_three_slots_per_date() -> None:
    """daily/monthly recurrence fans every candidate date out over the "all"
    key's slot list — three slots means three occurrences per date."""
    exp = ClassesExpander()
    cls = _class_with_slots(
        recurring_unit=RecurringUnit.daily,
        start_date=date(2025, 1, 1),
        weekday_slots={
            ALL_DAYS_KEY: [_slot(time(6, 0)), _slot(time(12, 0)), _slot(time(18, 0))]
        },
    )

    occ = exp.expand(cls, [], [], date(2025, 1, 1), date(2025, 1, 2), UTC_TZ)

    assert len(occ) == 6  # 2 dates * 3 slots
    for day in (date(2025, 1, 1), date(2025, 1, 2)):
        day_times = sorted(
            o.original_time for o in occ if o.effective_date == day
        )
        assert day_times == [time(6, 0), time(12, 0), time(18, 0)]


def test_instance_exception_bound_to_one_slot_leaves_sibling_untouched() -> (
    None
):
    """An exception bound to (date, 06:00) cancels/retimes ONLY that slot —
    the sibling 18:00 slot on the same date is unaffected."""
    exp = ClassesExpander()
    cls = _class_with_slots(
        recurring_unit=RecurringUnit.weekly,
        start_date=date(2025, 1, 6),
        weekday_slots={"mon": [_slot(time(6, 0)), _slot(time(18, 0))]},
    )
    # Cancel the 06:00 slot only.
    cancel = _instance(date(2025, 1, 6), time(6, 0), is_cancelled=True)
    cancelled_result = exp.expand(
        cls, [cancel], [], date(2025, 1, 6), date(2025, 1, 6), UTC_TZ
    )
    assert len(cancelled_result) == 1
    assert cancelled_result[0].original_time == time(18, 0)

    # Retime the 06:00 slot only.
    retime = _instance(date(2025, 1, 6), time(6, 0), new_class_time=time(7, 30))
    retimed_result = exp.expand(
        cls, [retime], [], date(2025, 1, 6), date(2025, 1, 6), UTC_TZ
    )
    assert len(retimed_result) == 2
    by_original = {o.original_time: o for o in retimed_result}
    assert by_original[time(6, 0)].class_time == time(7, 30)
    assert by_original[time(18, 0)].class_time == time(18, 0)  # untouched


def test_range_cancel_covers_all_slots_of_a_date() -> None:
    """A range cancel drops EVERY slot of a covered date; include_cancelled
    emits each one, flagged, independently."""
    exp = ClassesExpander()
    cls = _class_with_slots(
        recurring_unit=RecurringUnit.daily,
        start_date=date(2025, 1, 1),
        weekday_slots={ALL_DAYS_KEY: [_slot(time(6, 0)), _slot(time(18, 0))]},
    )
    rng = _range(date(2025, 1, 2), date(2025, 1, 2), is_cancelled=True)

    dropped = exp.expand(
        cls, [], [rng], date(2025, 1, 1), date(2025, 1, 3), UTC_TZ
    )
    assert {o.effective_date for o in dropped} == {
        date(2025, 1, 1),
        date(2025, 1, 3),
    }
    assert len([o for o in dropped if o.effective_date == date(2025, 1, 1)]) == 2

    shown = exp.expand(
        cls,
        [],
        [rng],
        date(2025, 1, 1),
        date(2025, 1, 3),
        UTC_TZ,
        include_cancelled=True,
    )
    cancelled = [o for o in shown if o.effective_date == date(2025, 1, 2)]
    assert len(cancelled) == 2
    assert all(o.is_cancelled for o in cancelled)
    assert {o.original_time for o in cancelled} == {time(6, 0), time(18, 0)}


def test_instructor_for_per_slot() -> None:
    """``instructor_for`` resolves the slot-default instructor of a specific
    (date, time) — an unknown slot time returns None."""
    exp = ClassesExpander()
    iid = uuid4()
    cls = _class_with_slots(
        recurring_unit=RecurringUnit.weekly,
        start_date=date(2025, 1, 6),
        weekday_slots={
            "mon": [_slot(time(6, 0), iid), _slot(time(18, 0))],
        },
    )

    assert exp.instructor_for(cls, date(2025, 1, 6), time(6, 0)) == iid
    assert exp.instructor_for(cls, date(2025, 1, 6), time(18, 0)) is None
    # A time that isn't one of the day's slots -> None.
    assert exp.instructor_for(cls, date(2025, 1, 6), time(9, 0)) is None
    # A weekday with no slots at all -> None.
    assert exp.instructor_for(cls, date(2025, 1, 7), time(6, 0)) is None


# -- the weekday_slots canonicalizer ---------------------------------------


class TestCanonicalizeWeekdaySlots:
    def test_dupe_times_rejected(self) -> None:
        with pytest.raises(ValueError, match="duplicate"):
            canonicalize_weekday_slots(
                {"mon": [_slot(time(6, 0)), _slot(time(6, 0))]},
                RecurringUnit.weekly,
            )

    def test_all_key_on_weekly_rejected(self) -> None:
        with pytest.raises(ValueError, match="invalid"):
            canonicalize_weekday_slots(
                {ALL_DAYS_KEY: [_slot(time(6, 0))]}, RecurringUnit.weekly
            )

    def test_weekday_key_on_daily_rejected(self) -> None:
        with pytest.raises(ValueError, match="invalid"):
            canonicalize_weekday_slots(
                {"mon": [_slot(time(6, 0))]}, RecurringUnit.daily
            )

    def test_empty_list_rejected(self) -> None:
        with pytest.raises(ValueError, match="must not be empty"):
            canonicalize_weekday_slots({"mon": []}, RecurringUnit.weekly)

    def test_weekly_with_no_days_rejected(self) -> None:
        with pytest.raises(ValueError, match="at least one weekday"):
            canonicalize_weekday_slots({}, RecurringUnit.weekly)

    def test_daily_missing_the_all_key_rejected(self) -> None:
        with pytest.raises(ValueError, match='"all"'):
            canonicalize_weekday_slots({}, RecurringUnit.daily)

    def test_lists_and_keys_are_returned_sorted(self) -> None:
        result = canonicalize_weekday_slots(
            {
                "wed": [_slot(time(18, 0)), _slot(time(6, 0))],
                "mon": [_slot(time(9, 0))],
            },
            RecurringUnit.weekly,
        )
        # Keys in canonical sun..sat order, and each list sorted by time.
        assert list(result.keys()) == ["mon", "wed"]
        assert [slot.time for slot in result["wed"]] == [time(6, 0), time(18, 0)]

    def test_equal_shapes_compare_equal_regardless_of_submission_order(
        self,
    ) -> None:
        """The canonicalizer's whole purpose: two submissions of the same
        shape in different key/list order canonicalize to the SAME dict —
        what the mint engine's deep-equal no-op check relies on."""
        a = canonicalize_weekday_slots(
            {
                "mon": [_slot(time(6, 0)), _slot(time(18, 0))],
                "wed": [_slot(time(9, 0))],
            },
            RecurringUnit.weekly,
        )
        b = canonicalize_weekday_slots(
            {
                "wed": [_slot(time(9, 0))],
                "mon": [_slot(time(18, 0)), _slot(time(6, 0))],
            },
            RecurringUnit.weekly,
        )
        assert a == b
