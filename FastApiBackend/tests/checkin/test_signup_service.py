"""Unit tests for SignupService (no DB).

Two collaborators are mocked: ``CheckinQueries`` (the class row / gym
timezone / instance-and-range-exception reads, and the shared
signed-up-or-attended union) and the raw ``db_pool`` session (the
insert/existing-lookup/delete writes). The real ``ClassesExpander`` is used
as-is — it's pure (no DB/IO), so exercising it directly gives the occurrence
validation tests (cancelled day vs. non-recurrence date vs. a real
occurrence) real expander behavior instead of a hand-rolled stand-in. This is
the capacity + occurrence-validation coverage that doesn't need the live
``class_signups`` table — see ``test_signup_integration.py`` for the
live-DB behavior (which needs the migration to be applied first).
"""

from datetime import date, datetime, time, timedelta
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest
from schema.gym_class import RecurringUnit

from src.checkin.service.signup_service import SignupService
from src.classes.service.classes_expander import ClassesExpander

_OCCURRENCE_DATE = date(2026, 6, 1)
_CREATED_AT = datetime(2025, 1, 1)


def _class_row(
    *,
    start_date: date = _OCCURRENCE_DATE - timedelta(days=1),
    end_date: date | None = None,
    recurring_unit: RecurringUnit = RecurringUnit.daily,
    recurring_interval: int = 1,
    max_capacity: int | None = None,
    exception_max_capacity: int | None = None,
    is_active: bool = True,
    is_deleted: bool = False,
) -> dict:
    """A gym_classes-shaped row (``classes_get_for_checkin.sql`` output).

    Defaults to a daily-recurring class that covers ``_OCCURRENCE_DATE`` — a
    real, non-cancelled occurrence — so tests only need to override the
    field(s) they care about.
    """
    row = {
        "class_id": uuid4(),
        "gym_id": uuid4(),
        "class_name": "Test Class",
        "class_time": time(10, 0),
        "duration_minutes": 30,
        "recurring_unit": recurring_unit,
        "recurring_interval": recurring_interval,
        "start_date": start_date,
        "end_date": end_date,
        "max_capacity": max_capacity,
        "allowed_plan_ids": None,
        "points_worth": 10,
        "is_active": is_active,
        "is_deleted": is_deleted,
        "exception_max_capacity": exception_max_capacity,
    }
    for day in ("sun", "mon", "tue", "wed", "thu", "fri", "sat"):
        row[day] = True
        row[f"{day}_instructor_id"] = None
    return row


def _instance_exception_row(
    *,
    original_date: date = _OCCURRENCE_DATE,
    is_cancelled: bool = True,
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
        "created_at": _CREATED_AT,
    }


def _result(row: dict | None) -> MagicMock:
    """A SQLAlchemy-result double whose ``.mappings().fetchone()`` is ``row``."""
    result = MagicMock()
    result.mappings.return_value.fetchone.return_value = row
    return result


def _service(
    class_row: dict | None,
    *,
    gym_tz: str | None = "America/Chicago",
    instances: list[dict] | None = None,
    ranges: list[dict] | None = None,
    write_results: list[MagicMock] | None = None,
) -> tuple[SignupService, AsyncMock]:
    """A SignupService with mocked queries + a mocked write session.

    ``write_results`` feeds ``session.execute`` (in order) for the raw
    insert/existing-lookup/delete SQL that ``_insert`` / ``remove`` still run
    directly against ``db_pool``. The class-load / gym-timezone /
    exception-list reads all go through the mocked ``_queries`` instead.
    """
    session = AsyncMock()
    session.__aenter__.return_value = session
    session.__aexit__.return_value = None
    session.execute = AsyncMock(side_effect=write_results or [])
    session.commit = AsyncMock()

    pool = MagicMock()
    pool.session.return_value = session

    service = SignupService(pool, ClassesExpander())
    service._queries = MagicMock()
    service._queries.get_class_for_checkin = AsyncMock(return_value=class_row)
    service._queries.get_gym_timezone = AsyncMock(return_value=gym_tz)
    service._queries.get_instance_exceptions = AsyncMock(
        return_value=instances or []
    )
    service._queries.get_range_exceptions = AsyncMock(return_value=ranges or [])
    return service, session


# ── occurrence validation ────────────────────────────────────────────


async def test_valid_occurrence_proceeds_to_insert() -> None:
    """A real, non-cancelled, unlimited-capacity occurrence -> allowed."""
    service, session = _service(
        _class_row(max_capacity=None),
        write_results=[_result({"signup_id": uuid4()})],
    )
    service._queries.get_signup_or_attended_members = AsyncMock()

    resp = await service.create(uuid4(), uuid4(), uuid4(), _OCCURRENCE_DATE)

    assert resp.already_signed_up is False


async def test_cancelled_day_is_rejected() -> None:
    """An instance exception cancelling the date -> rejected, distinct
    message from 'not a recurrence date'."""
    service, session = _service(
        _class_row(),
        instances=[_instance_exception_row(is_cancelled=True)],
    )

    with pytest.raises(ValueError, match="cancelled"):
        await service.create(uuid4(), uuid4(), uuid4(), _OCCURRENCE_DATE)

    session.execute.assert_not_called()


async def test_non_recurrence_date_is_rejected() -> None:
    """A date the class's recurrence never lands on -> rejected."""
    service, session = _service(
        _class_row(start_date=_OCCURRENCE_DATE + timedelta(days=1)),
    )

    with pytest.raises(ValueError, match="Not a class occurrence"):
        await service.create(uuid4(), uuid4(), uuid4(), _OCCURRENCE_DATE)

    session.execute.assert_not_called()


async def test_deleted_class_is_rejected() -> None:
    service, session = _service(_class_row(is_deleted=True))

    with pytest.raises(ValueError, match="deleted"):
        await service.create(uuid4(), uuid4(), uuid4(), _OCCURRENCE_DATE)

    session.execute.assert_not_called()


async def test_inactive_class_is_rejected() -> None:
    service, session = _service(_class_row(is_active=False))

    with pytest.raises(ValueError, match="not active"):
        await service.create(uuid4(), uuid4(), uuid4(), _OCCURRENCE_DATE)

    session.execute.assert_not_called()


async def test_unknown_class_raises_not_found() -> None:
    service, session = _service(None)
    service._queries.get_signup_or_attended_members = AsyncMock()

    with pytest.raises(ValueError, match="Class not found"):
        await service.create(uuid4(), uuid4(), uuid4(), _OCCURRENCE_DATE)


async def test_unknown_gym_raises_not_found() -> None:
    service, session = _service(_class_row(), gym_tz=None)

    with pytest.raises(ValueError, match="Gym not found"):
        await service.create(uuid4(), uuid4(), uuid4(), _OCCURRENCE_DATE)


# ── capacity ──────────────────────────────────────────────────────────


async def test_unlimited_capacity_always_inserts() -> None:
    """NULL max_capacity (and no instance-exception override) -> unlimited;
    the signed-up-or-attended union is never queried, straight to insert."""
    service, session = _service(
        _class_row(max_capacity=None),
        write_results=[_result({"signup_id": uuid4()})],
    )
    service._queries.get_signup_or_attended_members = AsyncMock()

    resp = await service.create(uuid4(), uuid4(), uuid4(), _OCCURRENCE_DATE)

    assert resp.already_signed_up is False
    service._queries.get_signup_or_attended_members.assert_not_awaited()


async def test_room_creates_when_under_capacity() -> None:
    """Effective capacity 5, union already has 2 (member not among them) ->
    room, inserts."""
    service, session = _service(
        _class_row(max_capacity=5),
        write_results=[_result({"signup_id": uuid4()})],
    )
    service._queries.get_signup_or_attended_members = AsyncMock(
        return_value={uuid4(), uuid4()}
    )

    resp = await service.create(uuid4(), uuid4(), uuid4(), _OCCURRENCE_DATE)

    assert resp.already_signed_up is False


async def test_full_room_rejects_a_new_member() -> None:
    """Effective capacity 2, union already has 2 OTHER members -> 'Class is
    full', and the insert is never attempted."""
    service, session = _service(_class_row(max_capacity=2))
    service._queries.get_signup_or_attended_members = AsyncMock(
        return_value={uuid4(), uuid4()}
    )

    with pytest.raises(ValueError, match="Class is full"):
        await service.create(uuid4(), uuid4(), uuid4(), _OCCURRENCE_DATE)

    session.execute.assert_not_called()  # never reached the insert


async def test_already_counted_member_bypasses_full_room() -> None:
    """A member already in the union (a prior sign-up, or already attended)
    is admitted even when the room is nominally full -- adding them doesn't
    grow the count."""
    member_id = uuid4()
    service, session = _service(
        _class_row(max_capacity=2),
        write_results=[_result({"signup_id": uuid4()})],
    )
    service._queries.get_signup_or_attended_members = AsyncMock(
        return_value={member_id, uuid4()}
    )

    resp = await service.create(member_id, uuid4(), uuid4(), _OCCURRENCE_DATE)

    assert resp.already_signed_up is False


async def test_exception_max_capacity_overrides_class_default() -> None:
    """A per-occurrence exception_max_capacity wins over the class default."""
    service, session = _service(
        _class_row(max_capacity=100, exception_max_capacity=1)
    )
    service._queries.get_signup_or_attended_members = AsyncMock(
        return_value={uuid4()}  # already 1/1 under the override
    )

    with pytest.raises(ValueError, match="Class is full"):
        await service.create(uuid4(), uuid4(), uuid4(), _OCCURRENCE_DATE)


# ── idempotent create ─────────────────────────────────────────────────


async def test_idempotent_repeat_returns_existing_signup_id() -> None:
    """ON CONFLICT DO NOTHING (no row) falls back to the existing-row lookup,
    reporting already_signed_up=True with the pre-existing id."""
    existing_id = uuid4()
    service, session = _service(
        _class_row(max_capacity=None),
        write_results=[
            _result(None),  # insert conflict
            _result({"signup_id": existing_id}),  # existing lookup
        ],
    )
    service._queries.get_signup_or_attended_members = AsyncMock()

    resp = await service.create(uuid4(), uuid4(), uuid4(), _OCCURRENCE_DATE)

    assert resp.signup_id == existing_id
    assert resp.already_signed_up is True


# ── remove ────────────────────────────────────────────────────────────


async def test_remove_returns_removed_true_when_row_deleted() -> None:
    service, session = _service(
        None, write_results=[_result({"signup_id": uuid4()})]
    )

    resp = await service.remove(uuid4(), uuid4(), uuid4(), _OCCURRENCE_DATE)

    assert resp.removed is True


async def test_remove_returns_removed_false_when_no_row() -> None:
    service, session = _service(None, write_results=[_result(None)])

    resp = await service.remove(uuid4(), uuid4(), uuid4(), _OCCURRENCE_DATE)

    assert resp.removed is False
