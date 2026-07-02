"""Unit tests for ``CheckinClassResolver`` (no DB).

Covers the effective-capacity resolution ``resolve`` folds into
``ResolvedClass.max_capacity`` — ``class_instance_exceptions.new_max_capacity``
overriding the class's ``max_capacity`` (NULL = unlimited) — the same
resolution ``SignupService`` runs for the sign-up path
(``test_signup_service.py``), mirrored here since it's the check-in capacity
gate's actual input; the ``ValueError`` mapping around a ``None`` resolution
(class not found / deleted / inactive / no real occurrence); and the
early-check-in window gate.

Occurrence resolution itself (the shared ``CheckinOccurrenceResolution`` —
window-widening for a rescheduled occurrence, cancelled-day handling, etc.)
is the canonical coverage of ``test_checkin_occurrence_resolution.py``; this
file builds a REAL ``CheckinOccurrenceResolution`` (with its own internal
``CheckinQueries`` mocked, the same pattern the old tests used) so the
resolver is exercised against real production wiring rather than a stubbed
seam, and keeps a couple of the reschedule cases here too since they're the
resolver's actual input shape.
"""

from datetime import UTC, date, datetime, time, timedelta
from unittest.mock import AsyncMock, MagicMock
from uuid import UUID, uuid4

import pytest
from schema.gym_class import RecurringUnit

from src.checkin.service.checkin_class_resolver import CheckinClassResolver
from src.checkin.service.checkin_occurrence_resolution import (
    CheckinOccurrenceResolution,
)
from src.classes.service.classes_expander import ClassesExpander
from src.classes.service.classes_version_expander import ClassesVersionExpander

# Well in the past, so the check-in-open window never blocks resolve()
# regardless of when the test actually runs; still inside the daily
# recurrence (start_date = this date - 1 day).
_OCCURRENCE_DATE = date(2020, 1, 2)
_EFFECTIVE_FROM = datetime(2019, 1, 1, tzinfo=UTC)


def _class_row(
    *,
    class_id: UUID,
    gym_id: UUID,
    max_capacity: int | None = None,
    exception_max_capacity: int | None = None,
    is_active: bool = True,
    is_deleted: bool = False,
) -> dict:
    """A classes_get_for_checkin.sql-shaped row (identity-only)."""
    return {
        "class_id": class_id,
        "gym_id": gym_id,
        "class_name": "Test Class",
        "max_capacity": max_capacity,
        "allowed_plan_ids": None,
        "points_worth": 10,
        "is_active": is_active,
        "is_deleted": is_deleted,
        "exception_max_capacity": exception_max_capacity,
    }


def _version_row(
    *,
    class_id: UUID,
    gym_id: UUID,
    start_date: date = _OCCURRENCE_DATE - timedelta(days=1),
    end_date: date | None = None,
    class_time: time = time(10, 0),
    duration_minutes: int = 30,
) -> dict:
    """A checkin_load_schedules.sql-shaped row: a daily-recurring class
    covering ``_OCCURRENCE_DATE``."""
    row = {
        "schedule_id": uuid4(),
        "class_id": class_id,
        "gym_id": gym_id,
        "effective_from": _EFFECTIVE_FROM,
        "timezone": "UTC",
        "class_time": class_time,
        "duration_minutes": duration_minutes,
        "recurring_unit": RecurringUnit.daily,
        "recurring_interval": 1,
        "start_date": start_date,
        "end_date": end_date,
    }
    for day in ("sun", "mon", "tue", "wed", "thu", "fri", "sat"):
        row[day] = True
        row[f"{day}_instructor_id"] = None
    return row


def _instance_exception_row(
    *,
    original_date: date,
    is_cancelled: bool = False,
    new_class_time: time | None = None,
    new_duration_minutes: int | None = None,
    new_instructor_id=None,
    new_date: date | None = None,
) -> dict:
    """A class_instance_exceptions-shaped row."""
    return {
        "original_date": original_date,
        "is_cancelled": is_cancelled,
        "new_class_time": new_class_time,
        "new_duration_minutes": new_duration_minutes,
        "new_instructor_id": new_instructor_id,
        "new_date": new_date,
        "created_at": datetime(2019, 1, 1),
    }


def _occurrence_resolution(
    *,
    versions: list[dict] | None = None,
    instances: list[dict] | None = None,
    ranges: list[dict] | None = None,
) -> CheckinOccurrenceResolution:
    """A REAL ``CheckinOccurrenceResolution`` with its internal
    ``CheckinQueries`` mocked — the shared, one-way ``checkin -> classes``
    resolution seam ``CheckinClassResolver`` injects."""
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


def _resolver(
    class_row: dict | None,
    *,
    versions: list[dict] | None = None,
    instances: list[dict] | None = None,
    ranges: list[dict] | None = None,
) -> CheckinClassResolver:
    resolver = CheckinClassResolver(
        MagicMock(),
        _occurrence_resolution(
            versions=versions, instances=instances, ranges=ranges
        ),
    )
    resolver._queries = MagicMock()
    resolver._queries.get_class_for_checkin = AsyncMock(return_value=class_row)
    return resolver


# ── effective capacity ──────────────────────────────────────────────────


async def test_exception_max_capacity_overrides_class_default() -> None:
    """A per-occurrence new_max_capacity wins over the class default."""
    class_id, gym_id = uuid4(), uuid4()
    resolver = _resolver(
        _class_row(
            class_id=class_id,
            gym_id=gym_id,
            max_capacity=100,
            exception_max_capacity=3,
        ),
        versions=[_version_row(class_id=class_id, gym_id=gym_id)],
    )

    resolved = await resolver.resolve(class_id, gym_id, _OCCURRENCE_DATE)

    assert resolved.max_capacity == 3


async def test_class_default_capacity_used_when_no_override() -> None:
    """No instance-exception override -> falls back to the class default."""
    class_id, gym_id = uuid4(), uuid4()
    resolver = _resolver(
        _class_row(
            class_id=class_id,
            gym_id=gym_id,
            max_capacity=20,
            exception_max_capacity=None,
        ),
        versions=[_version_row(class_id=class_id, gym_id=gym_id)],
    )

    resolved = await resolver.resolve(class_id, gym_id, _OCCURRENCE_DATE)

    assert resolved.max_capacity == 20


async def test_unlimited_capacity_when_both_none() -> None:
    """No class default and no override -> unlimited (None), never blocks."""
    class_id, gym_id = uuid4(), uuid4()
    resolver = _resolver(
        _class_row(
            class_id=class_id,
            gym_id=gym_id,
            max_capacity=None,
            exception_max_capacity=None,
        ),
        versions=[_version_row(class_id=class_id, gym_id=gym_id)],
    )

    resolved = await resolver.resolve(class_id, gym_id, _OCCURRENCE_DATE)

    assert resolved.max_capacity is None


# ── occurrence resolution ────────────────────────────────────────────────


async def test_class_not_found_raises() -> None:
    class_id, gym_id = uuid4(), uuid4()
    resolver = _resolver(None)

    with pytest.raises(ValueError, match="Class not found"):
        await resolver.resolve(class_id, gym_id, _OCCURRENCE_DATE)


async def test_deleted_class_raises() -> None:
    class_id, gym_id = uuid4(), uuid4()
    resolver = _resolver(
        _class_row(class_id=class_id, gym_id=gym_id, is_deleted=True)
    )

    with pytest.raises(ValueError, match="deleted"):
        await resolver.resolve(class_id, gym_id, _OCCURRENCE_DATE)


async def test_inactive_class_raises() -> None:
    class_id, gym_id = uuid4(), uuid4()
    resolver = _resolver(
        _class_row(class_id=class_id, gym_id=gym_id, is_active=False)
    )

    with pytest.raises(ValueError, match="not active"):
        await resolver.resolve(class_id, gym_id, _OCCURRENCE_DATE)


async def test_no_versions_raises_no_occurrence() -> None:
    """A class with no schedule versions at all has no occurrences."""
    class_id, gym_id = uuid4(), uuid4()
    resolver = _resolver(
        _class_row(class_id=class_id, gym_id=gym_id), versions=[]
    )

    with pytest.raises(ValueError, match="No class occurrence"):
        await resolver.resolve(class_id, gym_id, _OCCURRENCE_DATE)


async def test_non_recurrence_date_raises_no_occurrence() -> None:
    class_id, gym_id = uuid4(), uuid4()
    resolver = _resolver(
        _class_row(class_id=class_id, gym_id=gym_id),
        versions=[
            _version_row(
                class_id=class_id,
                gym_id=gym_id,
                start_date=_OCCURRENCE_DATE + timedelta(days=1),
            )
        ],
    )

    with pytest.raises(ValueError, match="No class occurrence"):
        await resolver.resolve(class_id, gym_id, _OCCURRENCE_DATE)


async def test_cancelled_occurrence_raises_no_occurrence() -> None:
    """A cancelled occurrence is dropped (include_cancelled=False, unlike
    the sign-up path), so it looks the same as no occurrence at all."""
    class_id, gym_id = uuid4(), uuid4()
    resolver = _resolver(
        _class_row(class_id=class_id, gym_id=gym_id),
        versions=[_version_row(class_id=class_id, gym_id=gym_id)],
        instances=[
            _instance_exception_row(
                original_date=_OCCURRENCE_DATE, is_cancelled=True
            )
        ],
    )

    with pytest.raises(ValueError, match="No class occurrence"):
        await resolver.resolve(class_id, gym_id, _OCCURRENCE_DATE)


async def test_rescheduled_occurrence_resolves_by_original_date() -> None:
    """An occurrence rescheduled to a DIFFERENT date still resolves when
    addressed by its ORIGINAL date — the window-widening fix. A bare
    ``[occurrence_date, occurrence_date]`` expand window would silently drop
    it (the reschedule's effective date falls outside that window)."""
    class_id, gym_id = uuid4(), uuid4()
    new_date = _OCCURRENCE_DATE + timedelta(days=10)
    resolver = _resolver(
        _class_row(class_id=class_id, gym_id=gym_id),
        versions=[_version_row(class_id=class_id, gym_id=gym_id)],
        instances=[
            _instance_exception_row(
                original_date=_OCCURRENCE_DATE, new_date=new_date
            )
        ],
    )

    resolved = await resolver.resolve(class_id, gym_id, _OCCURRENCE_DATE)

    assert resolved.occurrence_date == _OCCURRENCE_DATE
    assert resolved.occurred_at.date() == new_date


async def test_rescheduled_to_the_past_resolves_by_original_date() -> None:
    """The window-widening fix also handles a reschedule INTO the past."""
    class_id, gym_id = uuid4(), uuid4()
    new_date = _OCCURRENCE_DATE - timedelta(days=1)
    resolver = _resolver(
        _class_row(class_id=class_id, gym_id=gym_id),
        versions=[
            _version_row(
                class_id=class_id,
                gym_id=gym_id,
                start_date=new_date - timedelta(days=1),
            )
        ],
        instances=[
            _instance_exception_row(
                original_date=_OCCURRENCE_DATE, new_date=new_date
            )
        ],
    )

    resolved = await resolver.resolve(class_id, gym_id, _OCCURRENCE_DATE)

    assert resolved.occurrence_date == _OCCURRENCE_DATE
    assert resolved.occurred_at.date() == new_date


async def test_checkin_too_far_in_future_is_rejected() -> None:
    class_id, gym_id = uuid4(), uuid4()
    far_future = date.today() + timedelta(days=30)
    resolver = _resolver(
        _class_row(class_id=class_id, gym_id=gym_id),
        versions=[
            _version_row(
                class_id=class_id,
                gym_id=gym_id,
                start_date=far_future - timedelta(days=1),
            )
        ],
    )

    with pytest.raises(ValueError, match="not open yet"):
        await resolver.resolve(class_id, gym_id, far_future)
