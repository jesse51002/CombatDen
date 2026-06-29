"""Unit tests for points awarding + skip behavior in the gated check-in.

No DB / no Stripe: the writer is driven against a mocked session whose
``execute`` returns sequenced results, and the service skip path is driven with
mocked queries. Covers: points awarded exactly once on a NEW attendance row,
0 on an ON CONFLICT idempotent repeat, the class_attended activity_info shape,
and 0 points on a skip (capacity full / no membership).
"""

import json
from datetime import UTC, datetime
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

from src.classes.schema.classes_cycle_counts_schema import (
    ClassesCycleCountsResponse,
)
from src.classes.schema.classes_schema import (
    CheckinSkipReason,
    OccurrenceContext,
)
from src.classes.service.checkin.classes_checkin_service import (
    ClassesCheckinService,
)
from src.classes.service.checkin.classes_checkin_writer import (
    CLASS_ATTENDED_ACTIVITY_TYPE,
    ClassesCheckinWriter,
)


def _ctx(*, points_worth: int = 50, max_capacity: int | None = None) -> OccurrenceContext:
    """An OccurrenceContext with the fields the writer / service need."""
    return OccurrenceContext(
        class_history_id=uuid4(),
        class_id=uuid4(),
        gym_id=uuid4(),
        occurred_at=datetime(2026, 6, 1, 17, 0, tzinfo=UTC),
        points_worth=points_worth,
        class_name="Evening BJJ",
        max_capacity=max_capacity,
        allowed_plan_ids=None,
        instructor_id=None,
        duration_minutes=60,
    )


def _result(row: dict | None) -> MagicMock:
    """A SQLAlchemy-result double whose ``.mappings().fetchone()`` is ``row``."""
    result = MagicMock()
    result.mappings.return_value.fetchone.return_value = row
    return result


def _writer_with_results(results: list[MagicMock]) -> tuple[ClassesCheckinWriter, AsyncMock]:
    """A writer whose session.execute yields ``results`` in order."""
    session = AsyncMock()
    session.__aenter__.return_value = session
    session.__aexit__.return_value = None
    session.execute = AsyncMock(side_effect=results)
    session.commit = AsyncMock()

    pool = MagicMock()
    pool.session.return_value = session
    return ClassesCheckinWriter(pool), session


# ── writer: points awarded on a NEW row ──────────────────────────────


async def test_award_points_once_on_new_row() -> None:
    """A newly-inserted attendance row awards exactly points_worth, runs the
    points UPDATE + the class_attended activity INSERT, returns it."""
    ctx = _ctx(points_worth=75)
    member_id = uuid4()
    log_id = uuid4()
    # insert -> row, then last_class, award_points, insert_activity (no reads).
    writer, session = _writer_with_results(
        [_result({"log_id": log_id}), _result(None), _result(None), _result(None)]
    )

    result_log_id, already, points = await writer.write_checkin(
        ctx, member_id, uuid4(), uuid4(), should_end=False
    )

    assert result_log_id == log_id
    assert already is False
    assert points == 75

    # execute order: insert, last_class, award_points, insert_activity.
    assert session.execute.call_count == 4
    award_params = session.execute.call_args_list[2].args[1]
    assert award_params["points"] == 75
    assert award_params["m"] == str(member_id)
    assert award_params["g"] == str(ctx.gym_id)


async def test_activity_info_shape_on_new_row() -> None:
    """The class_attended activity carries {class_id, class_name, points}."""
    ctx = _ctx(points_worth=40)
    member_id = uuid4()
    writer, session = _writer_with_results(
        [_result({"log_id": uuid4()}), _result(None), _result(None), _result(None)]
    )

    await writer.write_checkin(ctx, member_id, uuid4(), uuid4(), should_end=False)

    activity_params = session.execute.call_args_list[3].args[1]
    assert activity_params["activity_type"] == CLASS_ATTENDED_ACTIVITY_TYPE
    assert activity_params["m"] == str(member_id)
    assert activity_params["g"] == str(ctx.gym_id)
    info = json.loads(activity_params["info"])
    assert info == {
        "class_id": str(ctx.class_id),
        "class_name": ctx.class_name,
        "points": 40,
    }


# ── writer: no points on an ON CONFLICT idempotent repeat ────────────


async def test_no_points_on_conflict() -> None:
    """An ON CONFLICT (no inserted row) awards nothing and runs no points /
    activity writes — only the insert + the existing-row read."""
    ctx = _ctx(points_worth=50)
    existing_log_id = uuid4()
    # insert -> None (conflict), then existing -> the stored row.
    writer, session = _writer_with_results(
        [
            _result(None),
            _result(
                {
                    "log_id": existing_log_id,
                    "plan_id": uuid4(),
                    "item_id": uuid4(),
                }
            ),
        ]
    )

    result_log_id, already, points = await writer.write_checkin(
        ctx, uuid4(), uuid4(), uuid4(), should_end=False
    )

    assert result_log_id == existing_log_id
    assert already is True
    assert points == 0
    # No award_points / insert_activity executed.
    assert session.execute.call_count == 2


# ── service: 0 points on a skip ──────────────────────────────────────


def _service_with_mocks() -> ClassesCheckinService:
    """A ClassesCheckinService whose collaborators are all mocked."""
    service = ClassesCheckinService(
        db_pool=MagicMock(),
        cycle_counts_service=MagicMock(),
        expander=MagicMock(),
        materializer=MagicMock(),
    )
    service._queries = MagicMock()
    service._queries.get_existing_attendance = AsyncMock(return_value=None)
    service._writer = MagicMock()
    service._writer.write_checkin = AsyncMock()
    return service


async def test_capacity_full_skip_awards_zero() -> None:
    """A full room skips a non-override check-in: 0 points, no write."""
    service = _service_with_mocks()
    service._queries.count_attendance = AsyncMock(return_value=10)
    ctx = _ctx(max_capacity=5)

    result = await service.checkin_member(ctx, uuid4(), allow_override=False)

    assert result.log_id is None
    assert result.points_awarded == 0
    assert result.skip_reason == CheckinSkipReason.capacity_full
    service._writer.write_checkin.assert_not_called()


async def test_no_membership_skip_awards_zero() -> None:
    """A member with no active membership skips: 0 points, no write."""
    service = _service_with_mocks()
    service._cycle_counts.get_cycle_counts = AsyncMock(
        return_value=ClassesCycleCountsResponse(users=[])
    )
    ctx = _ctx(max_capacity=None)

    result = await service.checkin_member(ctx, uuid4(), allow_override=False)

    assert result.log_id is None
    assert result.points_awarded == 0
    assert result.skip_reason == CheckinSkipReason.no_membership
    service._writer.write_checkin.assert_not_called()
