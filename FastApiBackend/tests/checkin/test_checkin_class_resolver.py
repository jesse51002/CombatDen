"""Unit tests for ``CheckinClassResolver`` (no DB).

Covers the effective-capacity resolution ``resolve`` folds into
``ResolvedClass.max_capacity`` — ``class_instance_exceptions.new_max_capacity``
overriding ``gym_classes.max_capacity`` (NULL = unlimited) — the same
resolution ``SignupService`` runs for the sign-up path
(``test_signup_service.py``), mirrored here since it's the check-in capacity
gate's actual input. The DB reads (class row / gym timezone / instance+range
exceptions) are mocked, along with ``ClassesMaterializer`` (its own behavior
is covered by ``test_classes_materializer.py``); the real ``ClassesExpander``
resolves the occurrence.
"""

from datetime import date, time, timedelta
from unittest.mock import AsyncMock, MagicMock
from uuid import UUID, uuid4

from schema.gym_class import RecurringUnit

from src.checkin.service.checkin_class_resolver import CheckinClassResolver
from src.classes.service.classes_expander import ClassesExpander

# Well in the past, so the check-in-open window never blocks resolve()
# regardless of when the test actually runs; still inside the daily
# recurrence (start_date = this date - 1 day).
_OCCURRENCE_DATE = date(2020, 1, 2)


def _class_row(
    *,
    class_id: UUID,
    gym_id: UUID,
    max_capacity: int | None = None,
    exception_max_capacity: int | None = None,
) -> dict:
    """A classes_get_for_checkin.sql-shaped row: a daily-recurring class
    covering ``_OCCURRENCE_DATE``, with the effective-capacity inputs."""
    row = {
        "class_id": class_id,
        "gym_id": gym_id,
        "class_name": "Test Class",
        "class_time": time(10, 0),
        "duration_minutes": 30,
        "recurring_unit": RecurringUnit.daily,
        "recurring_interval": 1,
        "start_date": _OCCURRENCE_DATE - timedelta(days=1),
        "end_date": None,
        "max_capacity": max_capacity,
        "allowed_plan_ids": None,
        "points_worth": 10,
        "is_active": True,
        "is_deleted": False,
        "exception_max_capacity": exception_max_capacity,
    }
    for day in ("sun", "mon", "tue", "wed", "thu", "fri", "sat"):
        row[day] = True
        row[f"{day}_instructor_id"] = None
    return row


def _resolver(class_row: dict) -> CheckinClassResolver:
    resolver = CheckinClassResolver(MagicMock(), ClassesExpander(), MagicMock())
    resolver._queries = MagicMock()
    resolver._queries.get_class_for_checkin = AsyncMock(return_value=class_row)
    resolver._queries.get_gym_timezone = AsyncMock(return_value="UTC")
    resolver._queries.get_instance_exceptions = AsyncMock(return_value=[])
    resolver._queries.get_range_exceptions = AsyncMock(return_value=[])
    resolver._materializer = MagicMock()
    resolver._materializer.materialize = AsyncMock(return_value=0)
    resolver._materializer.find_or_create_history = AsyncMock(
        return_value=(uuid4(), True)
    )
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
        )
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
        )
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
        )
    )

    resolved = await resolver.resolve(class_id, gym_id, _OCCURRENCE_DATE)

    assert resolved.max_capacity is None
