"""Unit tests for ``CheckinOccurrenceResolution`` (no DB) — the ONE
occurrence-resolution algorithm both ``CheckinClassResolver`` (check-in) and
``SignupService`` (sign-ups) inject, so the two can never disagree about
whether an occurrence exists.

This is the canonical coverage of the window-widening fix: an occurrence is
addressed by its ORIGINAL slot (date + time), never its effective
(post-reschedule) slot, so a naive ``[occurrence_date, occurrence_date]``
expand window would silently drop a rescheduled occurrence (the inner
expander filters on the EFFECTIVE date landing in-window).
``_resolution_window`` widens the window to also cover a reschedule's
``new_date`` before expanding once and filtering back to the exact original
slot. It's also the canonical coverage of the exact-slot match: a class may
occur several times on one day (``weekday_slots`` holds a slot list per
day), so ``resolve_original`` requires ``occurrence_time`` and matches
EXACTLY — never a first-match pick off the day's slots.

The DB reads (``CheckinQueries``) are mocked; the real
``ClassesVersionExpander`` (wrapping the real ``ClassesExpander``) resolves
the occurrence, so these tests exercise the real recurrence + exception
semantics, not a hand-rolled stand-in.
"""

from datetime import UTC, date, datetime, time, timedelta
from unittest.mock import AsyncMock, MagicMock
from uuid import UUID, uuid4

from schema.gym_class import RecurringUnit

from src.checkin.service.checkin_occurrence_resolution import (
    CheckinOccurrenceResolution,
)
from src.classes.schema.classes_expander_schema import ClassSlot
from src.classes.service.classes_expander import ClassesExpander
from src.classes.service.classes_version_expander import ClassesVersionExpander

_OCCURRENCE_DATE = date(2026, 6, 1)
_OCCURRENCE_TIME = time(10, 0)
_EFFECTIVE_FROM = datetime(2025, 1, 1, tzinfo=UTC)


def _version_row(
    class_id: UUID,
    gym_id: UUID,
    *,
    start_date: date = _OCCURRENCE_DATE - timedelta(days=365),
    end_date: date | None = None,
    slot_times: tuple[time, ...] = (_OCCURRENCE_TIME,),
    duration_minutes: int = 30,
) -> dict:
    """A ``checkin_load_schedules.sql``-shaped row: a daily-recurring class
    covering ``_OCCURRENCE_DATE``. ``slot_times`` may hold several times so a
    single day can carry multiple occurrences of the class."""
    return {
        "schedule_id": uuid4(),
        "class_id": class_id,
        "gym_id": gym_id,
        "effective_from": _EFFECTIVE_FROM,
        "timezone": "UTC",
        "duration_minutes": duration_minutes,
        "recurring_unit": RecurringUnit.daily,
        "recurring_interval": 1,
        "weekday_slots": {
            "all": [
                ClassSlot(time=t, instructor_id=None) for t in slot_times
            ]
        },
        "start_date": start_date,
        "end_date": end_date,
    }


def _instance_exception_row(
    *,
    original_date: date = _OCCURRENCE_DATE,
    original_time: time = _OCCURRENCE_TIME,
    is_cancelled: bool = False,
    new_class_time: time | None = None,
    new_duration_minutes: int | None = None,
    new_instructor_id=None,
    new_date: date | None = None,
) -> dict:
    """A ``class_instance_exceptions``-shaped row."""
    return {
        "original_date": original_date,
        "original_time": original_time,
        "is_cancelled": is_cancelled,
        "new_class_time": new_class_time,
        "new_duration_minutes": new_duration_minutes,
        "new_instructor_id": new_instructor_id,
        "new_date": new_date,
        "created_at": datetime(2025, 1, 1, tzinfo=UTC),
    }


def _resolution(
    *,
    versions: list[dict] | None = None,
    instances: list[dict] | None = None,
    ranges: list[dict] | None = None,
) -> CheckinOccurrenceResolution:
    resolution = CheckinOccurrenceResolution(
        MagicMock(), ClassesVersionExpander(ClassesExpander())
    )
    resolution._queries = MagicMock()
    resolution._queries.get_schedule_versions = AsyncMock(
        return_value=versions if versions is not None else []
    )

    async def _instances_for(_class_id, start_date, end_date):
        return [
            row
            for row in (instances or [])
            if start_date <= row["original_date"] <= end_date
        ]

    resolution._queries.get_instance_exceptions = AsyncMock(
        side_effect=_instances_for
    )
    resolution._queries.get_range_exceptions = AsyncMock(return_value=ranges or [])
    return resolution


# -- no versions / non-recurrence date ------------------------------------


async def test_no_versions_returns_none() -> None:
    """A class that has never been scheduled has no occurrences."""
    resolution = _resolution(versions=[])

    result = await resolution.resolve_original(
        uuid4(), _OCCURRENCE_DATE, _OCCURRENCE_TIME
    )

    assert result is None


async def test_non_recurrence_date_returns_none() -> None:
    """A date before the version's start_date is not a recurrence date."""
    class_id, gym_id = uuid4(), uuid4()
    resolution = _resolution(
        versions=[
            _version_row(
                class_id,
                gym_id,
                start_date=_OCCURRENCE_DATE + timedelta(days=1),
            )
        ]
    )

    result = await resolution.resolve_original(
        class_id, _OCCURRENCE_DATE, _OCCURRENCE_TIME
    )

    assert result is None


async def test_wrong_slot_time_returns_none() -> None:
    """A time that isn't one of the day's slots doesn't resolve, even though
    the date itself is a recurrence date."""
    class_id, gym_id = uuid4(), uuid4()
    resolution = _resolution(versions=[_version_row(class_id, gym_id)])

    result = await resolution.resolve_original(
        class_id, _OCCURRENCE_DATE, time(18, 30)
    )

    assert result is None


# -- plain (non-exception) occurrence --------------------------------------


async def test_plain_occurrence_resolves_without_needing_widening() -> None:
    """No exception on the date at all -> resolves straight through, no
    widening needed."""
    class_id, gym_id = uuid4(), uuid4()
    resolution = _resolution(versions=[_version_row(class_id, gym_id)])

    result = await resolution.resolve_original(
        class_id, _OCCURRENCE_DATE, _OCCURRENCE_TIME
    )

    assert result is not None
    assert result.original_date == _OCCURRENCE_DATE
    assert result.effective_date == _OCCURRENCE_DATE


# -- two slots on the same day -- exact-slot matching -----------------------


async def test_two_same_day_slots_resolve_independently_by_time() -> None:
    """A class with two slots on one day: each resolves EXACTLY by its own
    time, never a first-match off the day's slot list."""
    class_id, gym_id = uuid4(), uuid4()
    morning, evening = time(6, 0), time(18, 30)
    resolution = _resolution(
        versions=[_version_row(class_id, gym_id, slot_times=(morning, evening))]
    )

    morning_occ = await resolution.resolve_original(
        class_id, _OCCURRENCE_DATE, morning
    )
    evening_occ = await resolution.resolve_original(
        class_id, _OCCURRENCE_DATE, evening
    )

    assert morning_occ is not None and evening_occ is not None
    assert morning_occ.original_time == morning
    assert evening_occ.original_time == evening


async def test_two_same_day_slots_exceptions_apply_independently() -> None:
    """An instance exception bound to ONE slot's exact time never touches a
    same-day sibling slot's resolution."""
    class_id, gym_id = uuid4(), uuid4()
    morning, evening = time(6, 0), time(18, 30)
    resolution = _resolution(
        versions=[_version_row(class_id, gym_id, slot_times=(morning, evening))],
        instances=[
            _instance_exception_row(
                original_date=_OCCURRENCE_DATE,
                original_time=morning,
                is_cancelled=True,
            )
        ],
    )

    # The cancelled morning slot no longer resolves...
    morning_occ = await resolution.resolve_original(
        class_id, _OCCURRENCE_DATE, morning
    )
    assert morning_occ is None

    # ...but the untouched evening slot still resolves cleanly.
    evening_occ = await resolution.resolve_original(
        class_id, _OCCURRENCE_DATE, evening
    )
    assert evening_occ is not None
    assert evening_occ.is_cancelled is False


# -- cancelled --------------------------------------------------------------


async def test_cancelled_occurrence_returns_none_by_default() -> None:
    """The default include_cancelled=False drops a cancelled occurrence —
    indistinguishable from "not a recurrence date" to the caller."""
    class_id, gym_id = uuid4(), uuid4()
    resolution = _resolution(
        versions=[_version_row(class_id, gym_id)],
        instances=[
            _instance_exception_row(
                original_date=_OCCURRENCE_DATE,
                original_time=_OCCURRENCE_TIME,
                is_cancelled=True,
            )
        ],
    )

    result = await resolution.resolve_original(
        class_id, _OCCURRENCE_DATE, _OCCURRENCE_TIME
    )

    assert result is None


async def test_cancelled_occurrence_returned_flagged_when_include_cancelled() -> (
    None
):
    """include_cancelled=True (the sign-up path) returns the occurrence
    flagged instead of dropping it, so the caller can distinguish "cancelled
    that day" from "never a recurrence date" in its own error message."""
    class_id, gym_id = uuid4(), uuid4()
    resolution = _resolution(
        versions=[_version_row(class_id, gym_id)],
        instances=[
            _instance_exception_row(
                original_date=_OCCURRENCE_DATE,
                original_time=_OCCURRENCE_TIME,
                is_cancelled=True,
            )
        ],
    )

    result = await resolution.resolve_original(
        class_id, _OCCURRENCE_DATE, _OCCURRENCE_TIME, include_cancelled=True
    )

    assert result is not None
    assert result.is_cancelled is True
    assert result.original_date == _OCCURRENCE_DATE


# -- window-widening (the reschedule fix) ------------------------------


async def test_rescheduled_occurrence_resolves_by_original_date() -> None:
    """An occurrence rescheduled to a DIFFERENT (future) date still resolves
    when addressed by its ORIGINAL slot — the window-widening fix. A bare
    ``[occurrence_date, occurrence_date]`` expand window would silently drop
    it (the reschedule's effective date falls outside that window)."""
    class_id, gym_id = uuid4(), uuid4()
    new_date = _OCCURRENCE_DATE + timedelta(days=10)
    resolution = _resolution(
        versions=[_version_row(class_id, gym_id)],
        instances=[
            _instance_exception_row(
                original_date=_OCCURRENCE_DATE,
                original_time=_OCCURRENCE_TIME,
                new_date=new_date,
            )
        ],
    )

    result = await resolution.resolve_original(
        class_id, _OCCURRENCE_DATE, _OCCURRENCE_TIME
    )

    assert result is not None
    assert result.original_date == _OCCURRENCE_DATE
    assert result.effective_date == new_date
    assert result.occurred_at.date() == new_date
    assert result.is_rescheduled is True


async def test_rescheduled_to_the_past_resolves_by_original_date() -> None:
    """The window-widening fix also handles a reschedule INTO the past."""
    class_id, gym_id = uuid4(), uuid4()
    new_date = _OCCURRENCE_DATE - timedelta(days=200)
    resolution = _resolution(
        versions=[
            _version_row(
                class_id, gym_id, start_date=new_date - timedelta(days=1)
            )
        ],
        instances=[
            _instance_exception_row(
                original_date=_OCCURRENCE_DATE,
                original_time=_OCCURRENCE_TIME,
                new_date=new_date,
            )
        ],
    )

    result = await resolution.resolve_original(
        class_id, _OCCURRENCE_DATE, _OCCURRENCE_TIME
    )

    assert result is not None
    assert result.original_date == _OCCURRENCE_DATE
    assert result.effective_date == new_date
    assert result.occurred_at.date() == new_date


async def test_resolution_window_widens_to_cover_new_date_both_directions() -> (
    None
):
    """``_resolution_window`` widens using min/max of the original and
    target dates regardless of which direction the move goes."""
    class_id, gym_id = uuid4(), uuid4()
    new_date = _OCCURRENCE_DATE + timedelta(days=3)
    resolution = _resolution(
        versions=[_version_row(class_id, gym_id)],
        instances=[
            _instance_exception_row(
                original_date=_OCCURRENCE_DATE,
                original_time=_OCCURRENCE_TIME,
                new_date=new_date,
            )
        ],
    )

    window_start, window_end = await resolution._resolution_window(
        class_id, _OCCURRENCE_DATE, _OCCURRENCE_TIME
    )

    assert window_start == _OCCURRENCE_DATE
    assert window_end == new_date


async def test_resolution_window_is_unwidened_without_a_reschedule() -> None:
    """No exception (or a non-reschedule override) on the date -> the window
    stays exactly ``[occurrence_date, occurrence_date]``."""
    class_id, gym_id = uuid4(), uuid4()
    resolution = _resolution(versions=[_version_row(class_id, gym_id)])

    window_start, window_end = await resolution._resolution_window(
        class_id, _OCCURRENCE_DATE, _OCCURRENCE_TIME
    )

    assert window_start == window_end == _OCCURRENCE_DATE


async def test_resolution_window_picks_the_exception_matching_this_slot() -> (
    None
):
    """Two same-day exceptions (one per slot) -> the window widens using
    ONLY the exception bound to the requested slot's exact time, never the
    day's first exception."""
    class_id, gym_id = uuid4(), uuid4()
    morning, evening = time(6, 0), time(18, 30)
    evening_new_date = _OCCURRENCE_DATE + timedelta(days=5)
    resolution = _resolution(
        versions=[_version_row(class_id, gym_id, slot_times=(morning, evening))],
        instances=[
            # Morning slot: cancelled, no reschedule.
            _instance_exception_row(
                original_date=_OCCURRENCE_DATE,
                original_time=morning,
                is_cancelled=True,
            ),
            # Evening slot: rescheduled.
            _instance_exception_row(
                original_date=_OCCURRENCE_DATE,
                original_time=evening,
                new_date=evening_new_date,
            ),
        ],
    )

    morning_window = await resolution._resolution_window(
        class_id, _OCCURRENCE_DATE, morning
    )
    evening_window = await resolution._resolution_window(
        class_id, _OCCURRENCE_DATE, evening
    )

    assert morning_window == (_OCCURRENCE_DATE, _OCCURRENCE_DATE)
    assert evening_window == (_OCCURRENCE_DATE, evening_new_date)
