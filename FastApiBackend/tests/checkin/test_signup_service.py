"""Unit tests for SignupService (no DB) — capacity + occurrence validation.

``CheckinQueries`` (the class read + the signed-up-or-attended union) and the
``db_pool`` session are mocked on the service, but occurrence resolution runs
through a REAL ``CheckinOccurrenceResolution`` (only ITS ``CheckinQueries``
mocked) so the expander behaviour is production wiring, not a stand-in. The
resolution algorithm itself is covered by
``test_checkin_occurrence_resolution.py``, live ``class_signups`` behaviour by
``test_signup_integration.py``, and the type -> status contract by
``test_checkin_error_mapping.py``.
"""

from datetime import date, datetime, time, timedelta
from unittest.mock import AsyncMock, MagicMock
from uuid import UUID, uuid4

import pytest
from schema.gym_class import RecurringUnit

from src.checkin.checkin_exceptions import (
    CheckinClassDeletedError,
    CheckinClassFullError,
    CheckinClassInactiveError,
    CheckinClassNotFoundError,
    CheckinOccurrenceCancelledError,
    CheckinOccurrenceNotFoundError,
)
from src.checkin.service.checkin_occurrence_resolution import (
    CheckinOccurrenceResolution,
)
from src.checkin.service.signup_service import SignupService
from src.classes.schema.classes_expander_schema import ClassSlot
from src.classes.service.classes_expander import ClassesExpander
from src.classes.service.classes_version_expander import ClassesVersionExpander

_OCCURRENCE_DATE = date(2026, 6, 1)
_OCCURRENCE_TIME = time(10, 0)
_EFFECTIVE_FROM = datetime(2025, 1, 1)
_CREATED_AT = datetime(2025, 1, 1)


def _class_row(
    *,
    max_capacity: int | None = None,
    exception_max_capacity: int | None = None,
    is_active: bool = True,
    is_deleted: bool = False,
) -> dict:
    """A gym_classes-shaped row (``classes_get_for_checkin.sql`` output,
    identity-only)."""
    return {
        "class_id": uuid4(),
        "gym_id": uuid4(),
        "class_name": "Test Class",
        "max_capacity": max_capacity,
        "allowed_plan_ids": None,
        "points_worth": 10,
        "is_active": is_active,
        "is_deleted": is_deleted,
        "exception_max_capacity": exception_max_capacity,
    }


def _version_row(
    class_id: UUID,
    gym_id: UUID,
    *,
    start_date: date = _OCCURRENCE_DATE - timedelta(days=1),
    end_date: date | None = None,
    recurring_unit: RecurringUnit = RecurringUnit.daily,
    recurring_interval: int = 1,
    slot_times: tuple[time, ...] = (_OCCURRENCE_TIME,),
) -> dict:
    """A daily class covering ``_OCCURRENCE_DATE`` (a real, non-cancelled
    occurrence). Several ``slot_times`` = several occurrences a day."""
    return {
        "schedule_id": uuid4(),
        "class_id": class_id,
        "gym_id": gym_id,
        "effective_from": _EFFECTIVE_FROM,
        "timezone": "UTC",
        "duration_minutes": 30,
        "recurring_unit": recurring_unit,
        "recurring_interval": recurring_interval,
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
    is_cancelled: bool = True,
    new_class_time: time | None = None,
    new_duration_minutes: int | None = None,
    new_instructor_id=None,
    new_date: date | None = None,
) -> dict:
    """A class_instance_exceptions-shaped row."""
    return {
        "original_date": original_date,
        "original_time": original_time,
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
    versions: list[dict] | None = None,
    instances: list[dict] | None = None,
    ranges: list[dict] | None = None,
    write_results: list[MagicMock] | None = None,
) -> tuple[SignupService, AsyncMock]:
    """A SignupService with mocked queries + a mocked write session.

    ``write_results`` feeds ``session.execute`` in order for the raw
    insert/existing-lookup/delete SQL; the reads go through ``_queries``.
    """
    session = AsyncMock()
    session.__aenter__.return_value = session
    session.__aexit__.return_value = None
    session.execute = AsyncMock(side_effect=write_results or [])
    session.commit = AsyncMock()

    pool = MagicMock()
    pool.session.return_value = session

    occurrence_resolution = CheckinOccurrenceResolution(
        MagicMock(), ClassesVersionExpander(ClassesExpander())
    )
    occurrence_resolution._queries = MagicMock()
    occurrence_resolution._queries.get_schedule_versions = AsyncMock(
        return_value=versions if versions is not None else []
    )

    async def _instances_for(_class_id, start_date, end_date):
        return [
            row
            for row in (instances or [])
            if start_date <= row["original_date"] <= end_date
        ]

    occurrence_resolution._queries.get_instance_exceptions = AsyncMock(
        side_effect=_instances_for
    )
    occurrence_resolution._queries.get_range_exceptions = AsyncMock(
        return_value=ranges or []
    )

    service = SignupService(pool, occurrence_resolution)
    service._queries = MagicMock()
    service._queries.get_class_for_checkin = AsyncMock(return_value=class_row)
    return service, session


# ── occurrence validation ────────────────────────────────────────────


async def test_valid_occurrence_proceeds_to_insert() -> None:
    """A real, non-cancelled, unlimited-capacity occurrence -> allowed."""
    class_row = _class_row(max_capacity=None)
    service, session = _service(
        class_row,
        versions=[_version_row(class_row["class_id"], class_row["gym_id"])],
        write_results=[_result({"signup_id": uuid4()})],
    )
    service._queries.get_signup_or_attended_members = AsyncMock()

    resp = await service.create(
        uuid4(), uuid4(), uuid4(), _OCCURRENCE_DATE, _OCCURRENCE_TIME
    )

    assert resp.already_signed_up is False


async def test_cancelled_day_is_rejected() -> None:
    """A cancelled date is its own rejection type, distinct from
    'not a recurrence date'."""
    class_row = _class_row()
    service, session = _service(
        class_row,
        versions=[_version_row(class_row["class_id"], class_row["gym_id"])],
        instances=[_instance_exception_row(is_cancelled=True)],
    )

    with pytest.raises(CheckinOccurrenceCancelledError, match="cancelled"):
        await service.create(
            uuid4(), uuid4(), uuid4(), _OCCURRENCE_DATE, _OCCURRENCE_TIME
        )

    session.execute.assert_not_called()


async def test_non_recurrence_date_is_rejected() -> None:
    """A date the class's recurrence never lands on -> rejected."""
    class_row = _class_row()
    service, session = _service(
        class_row,
        versions=[
            _version_row(
                class_row["class_id"],
                class_row["gym_id"],
                start_date=_OCCURRENCE_DATE + timedelta(days=1),
            )
        ],
    )

    with pytest.raises(CheckinOccurrenceNotFoundError, match="Not a class occurrence"):
        await service.create(
            uuid4(), uuid4(), uuid4(), _OCCURRENCE_DATE, _OCCURRENCE_TIME
        )

    session.execute.assert_not_called()


async def test_wrong_slot_time_is_rejected() -> None:
    """A time that isn't one of the day's slots -> rejected, even though the
    date itself is a recurrence date."""
    class_row = _class_row()
    service, session = _service(
        class_row,
        versions=[_version_row(class_row["class_id"], class_row["gym_id"])],
    )

    with pytest.raises(CheckinOccurrenceNotFoundError, match="Not a class occurrence"):
        await service.create(
            uuid4(), uuid4(), uuid4(), _OCCURRENCE_DATE, time(18, 30)
        )

    session.execute.assert_not_called()


async def test_no_versions_is_rejected() -> None:
    """A class that has never been scheduled has no occurrences."""
    class_row = _class_row()
    service, session = _service(class_row, versions=[])

    with pytest.raises(CheckinOccurrenceNotFoundError, match="Not a class occurrence"):
        await service.create(
            uuid4(), uuid4(), uuid4(), _OCCURRENCE_DATE, _OCCURRENCE_TIME
        )

    session.execute.assert_not_called()


async def test_deleted_class_is_rejected() -> None:
    service, session = _service(_class_row(is_deleted=True))

    with pytest.raises(CheckinClassDeletedError, match="deleted"):
        await service.create(
            uuid4(), uuid4(), uuid4(), _OCCURRENCE_DATE, _OCCURRENCE_TIME
        )

    session.execute.assert_not_called()


async def test_inactive_class_is_rejected() -> None:
    service, session = _service(_class_row(is_active=False))

    with pytest.raises(CheckinClassInactiveError, match="not active"):
        await service.create(
            uuid4(), uuid4(), uuid4(), _OCCURRENCE_DATE, _OCCURRENCE_TIME
        )

    session.execute.assert_not_called()


async def test_unknown_class_raises_not_found() -> None:
    service, session = _service(None)
    service._queries.get_signup_or_attended_members = AsyncMock()

    with pytest.raises(CheckinClassNotFoundError, match="Class not found"):
        await service.create(
            uuid4(), uuid4(), uuid4(), _OCCURRENCE_DATE, _OCCURRENCE_TIME
        )


async def test_rescheduled_occurrence_resolves_by_original_date() -> None:
    """An occurrence rescheduled to a DIFFERENT date is still a valid sign-up
    target when addressed by its ORIGINAL date (the widened expand window)."""
    class_row = _class_row(max_capacity=None)
    new_date = _OCCURRENCE_DATE + timedelta(days=5)
    service, session = _service(
        class_row,
        versions=[_version_row(class_row["class_id"], class_row["gym_id"])],
        instances=[
            _instance_exception_row(
                original_date=_OCCURRENCE_DATE,
                is_cancelled=False,
                new_date=new_date,
            )
        ],
        write_results=[_result({"signup_id": uuid4()})],
    )
    service._queries.get_signup_or_attended_members = AsyncMock()

    resp = await service.create(
        uuid4(), uuid4(), uuid4(), _OCCURRENCE_DATE, _OCCURRENCE_TIME
    )

    assert resp.already_signed_up is False
    insert_params = session.execute.call_args_list[0].args[1]
    assert insert_params["original_date"] == _OCCURRENCE_DATE


async def test_two_same_day_slots_signup_independently() -> None:
    """One slot's cancellation never blocks its same-day sibling's sign-up."""
    class_row = _class_row(max_capacity=None)
    morning, evening = time(6, 0), time(18, 30)
    service, session = _service(
        class_row,
        versions=[
            _version_row(
                class_row["class_id"],
                class_row["gym_id"],
                slot_times=(morning, evening),
            )
        ],
        instances=[
            _instance_exception_row(
                original_date=_OCCURRENCE_DATE,
                original_time=morning,
                is_cancelled=True,
            )
        ],
        write_results=[_result({"signup_id": uuid4()})],
    )
    service._queries.get_signup_or_attended_members = AsyncMock()

    # The evening slot (untouched) still signs up cleanly.
    resp = await service.create(
        uuid4(), uuid4(), uuid4(), _OCCURRENCE_DATE, evening
    )

    assert resp.already_signed_up is False
    insert_params = session.execute.call_args_list[0].args[1]
    assert insert_params["original_time"] == evening


async def test_two_same_day_slots_cancelled_morning_rejected() -> None:
    class_row = _class_row(max_capacity=None)
    morning, evening = time(6, 0), time(18, 30)
    service, session = _service(
        class_row,
        versions=[
            _version_row(
                class_row["class_id"],
                class_row["gym_id"],
                slot_times=(morning, evening),
            )
        ],
        instances=[
            _instance_exception_row(
                original_date=_OCCURRENCE_DATE,
                original_time=morning,
                is_cancelled=True,
            )
        ],
    )

    with pytest.raises(CheckinOccurrenceCancelledError, match="cancelled"):
        await service.create(uuid4(), uuid4(), uuid4(), _OCCURRENCE_DATE, morning)

    session.execute.assert_not_called()


# ── capacity ──────────────────────────────────────────────────────────


async def test_unlimited_capacity_always_inserts() -> None:
    """Unlimited capacity never queries the union — straight to the insert."""
    class_row = _class_row(max_capacity=None)
    service, session = _service(
        class_row,
        versions=[_version_row(class_row["class_id"], class_row["gym_id"])],
        write_results=[_result({"signup_id": uuid4()})],
    )
    service._queries.get_signup_or_attended_members = AsyncMock()

    resp = await service.create(
        uuid4(), uuid4(), uuid4(), _OCCURRENCE_DATE, _OCCURRENCE_TIME
    )

    assert resp.already_signed_up is False
    service._queries.get_signup_or_attended_members.assert_not_awaited()


async def test_room_creates_when_under_capacity() -> None:
    """Effective capacity 5, union already has 2 (member not among them) ->
    room, inserts."""
    class_row = _class_row(max_capacity=5)
    service, session = _service(
        class_row,
        versions=[_version_row(class_row["class_id"], class_row["gym_id"])],
        write_results=[_result({"signup_id": uuid4()})],
    )
    service._queries.get_signup_or_attended_members = AsyncMock(
        return_value={uuid4(), uuid4()}
    )

    resp = await service.create(
        uuid4(), uuid4(), uuid4(), _OCCURRENCE_DATE, _OCCURRENCE_TIME
    )

    assert resp.already_signed_up is False


async def test_full_room_rejects_a_new_member() -> None:
    """Effective capacity 2, union already has 2 OTHER members -> 'Class is
    full', and the insert is never attempted."""
    class_row = _class_row(max_capacity=2)
    service, session = _service(
        class_row,
        versions=[_version_row(class_row["class_id"], class_row["gym_id"])],
    )
    service._queries.get_signup_or_attended_members = AsyncMock(
        return_value={uuid4(), uuid4()}
    )

    with pytest.raises(CheckinClassFullError, match="Class is full"):
        await service.create(
            uuid4(), uuid4(), uuid4(), _OCCURRENCE_DATE, _OCCURRENCE_TIME
        )

    session.execute.assert_not_called()  # never reached the insert


async def test_already_counted_member_bypasses_full_room() -> None:
    """A member already in the union is admitted even when the room is
    nominally full — re-adding them can't grow the count."""
    member_id = uuid4()
    class_row = _class_row(max_capacity=2)
    service, session = _service(
        class_row,
        versions=[_version_row(class_row["class_id"], class_row["gym_id"])],
        write_results=[_result({"signup_id": uuid4()})],
    )
    service._queries.get_signup_or_attended_members = AsyncMock(
        return_value={member_id, uuid4()}
    )

    resp = await service.create(
        member_id, uuid4(), uuid4(), _OCCURRENCE_DATE, _OCCURRENCE_TIME
    )

    assert resp.already_signed_up is False


async def test_exception_max_capacity_overrides_class_default() -> None:
    """A per-occurrence exception_max_capacity wins over the class default."""
    class_row = _class_row(max_capacity=100, exception_max_capacity=1)
    service, session = _service(
        class_row,
        versions=[_version_row(class_row["class_id"], class_row["gym_id"])],
    )
    service._queries.get_signup_or_attended_members = AsyncMock(
        return_value={uuid4()}  # already 1/1 under the override
    )

    with pytest.raises(CheckinClassFullError, match="Class is full"):
        await service.create(
            uuid4(), uuid4(), uuid4(), _OCCURRENCE_DATE, _OCCURRENCE_TIME
        )


async def test_capacity_pools_are_independent_per_slot() -> None:
    """Capacity pools are per exact slot: a full morning never blocks the
    evening, because the union is asked with THIS slot's own time."""
    class_row = _class_row(max_capacity=1)
    morning, evening = time(6, 0), time(18, 30)
    service, session = _service(
        class_row,
        versions=[
            _version_row(
                class_row["class_id"],
                class_row["gym_id"],
                slot_times=(morning, evening),
            )
        ],
        write_results=[_result({"signup_id": uuid4()})],
    )
    # The fake union doesn't filter by slot, so the assertion below is that the
    # SERVICE passes the right occurrence_time through.
    union_mock = AsyncMock(return_value=set())
    service._queries.get_signup_or_attended_members = union_mock

    resp = await service.create(
        uuid4(), uuid4(), uuid4(), _OCCURRENCE_DATE, evening
    )

    assert resp.already_signed_up is False
    union_mock.assert_awaited_once()
    call_args = union_mock.await_args.args
    assert call_args[-1] == evening


# ── idempotent create ─────────────────────────────────────────────────


async def test_idempotent_repeat_returns_existing_signup_id() -> None:
    """ON CONFLICT DO NOTHING (no row) falls back to the existing-row lookup,
    reporting already_signed_up=True with the pre-existing id."""
    existing_id = uuid4()
    class_row = _class_row(max_capacity=None)
    service, session = _service(
        class_row,
        versions=[_version_row(class_row["class_id"], class_row["gym_id"])],
        write_results=[
            _result(None),  # insert conflict
            _result({"signup_id": existing_id}),  # existing lookup
        ],
    )
    service._queries.get_signup_or_attended_members = AsyncMock()

    resp = await service.create(
        uuid4(), uuid4(), uuid4(), _OCCURRENCE_DATE, _OCCURRENCE_TIME
    )

    assert resp.signup_id == existing_id
    assert resp.already_signed_up is True


# ── remove ────────────────────────────────────────────────────────────


async def test_remove_returns_removed_true_when_row_deleted() -> None:
    service, session = _service(
        None, write_results=[_result({"signup_id": uuid4()})]
    )

    resp = await service.remove(
        uuid4(), uuid4(), uuid4(), _OCCURRENCE_DATE, _OCCURRENCE_TIME
    )

    assert resp.removed is True


async def test_remove_returns_removed_false_when_no_row() -> None:
    service, session = _service(None, write_results=[_result(None)])

    resp = await service.remove(
        uuid4(), uuid4(), uuid4(), _OCCURRENCE_DATE, _OCCURRENCE_TIME
    )

    assert resp.removed is False
