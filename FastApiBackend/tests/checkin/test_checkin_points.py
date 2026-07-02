"""Unit tests for the check-in writer's points + NULL-attribution behavior.

No DB / no Stripe: the writer is driven against a mocked session whose
``execute`` returns sequenced results. Covers: points awarded exactly once on a
NEW attendance row (membership or not), 0 on an ON CONFLICT idempotent repeat,
the class_attended activity_info shape, and a NULL-attribution write (a staff
check-in of a member with no membership binds plan_id/item_id as NULL but still
awards points).

The gate's block-vs-warn behavior is unit-tested in
``checkin/test_checkin_member_gate.py``.
"""

import json
from datetime import UTC, date, datetime, time
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

from src.checkin.schema.checkin_schema import ResolvedClass
from src.checkin.service.checkin_writer import (
    CLASS_ATTENDED_ACTIVITY_TYPE,
    CheckinWriter,
)


def _resolved_class(
    *, points_worth: int = 50, max_capacity: int | None = None
) -> ResolvedClass:
    """A ResolvedClass with the fields the writer needs."""
    return ResolvedClass(
        class_id=uuid4(),
        gym_id=uuid4(),
        occurrence_date=date(2026, 6, 1),
        original_time=time(17, 0),
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


def _writer_with_results(results: list[MagicMock]) -> tuple[CheckinWriter, AsyncMock]:
    """A writer whose session.execute yields ``results`` in order."""
    session = AsyncMock()
    session.__aenter__.return_value = session
    session.__aexit__.return_value = None
    session.execute = AsyncMock(side_effect=results)
    session.commit = AsyncMock()

    pool = MagicMock()
    pool.session.return_value = session
    return CheckinWriter(pool), session


# ── writer: points awarded on a NEW row ──────────────────────────────


async def test_award_points_once_on_new_row() -> None:
    """A newly-inserted attendance row awards exactly points_worth, runs the
    points UPDATE + the class_attended activity INSERT, returns it."""
    resolved_class = _resolved_class(points_worth=75)
    member_id = uuid4()
    log_id = uuid4()
    # insert -> row, then last_class, award_points, insert_activity (no reads).
    writer, session = _writer_with_results(
        [_result({"log_id": log_id}), _result(None), _result(None), _result(None)]
    )

    result_log_id, already, points = await writer.write_checkin(
        resolved_class, member_id, uuid4(), uuid4(), should_end=False
    )

    assert result_log_id == log_id
    assert already is False
    assert points == 75

    # execute order: insert, last_class, award_points, insert_activity.
    assert session.execute.call_count == 4
    award_params = session.execute.call_args_list[2].args[1]
    assert award_params["points"] == 75
    assert award_params["m"] == str(member_id)
    assert award_params["g"] == str(resolved_class.gym_id)


async def test_activity_info_shape_on_new_row() -> None:
    """The class_attended activity carries {class_id, class_name, points}."""
    resolved_class = _resolved_class(points_worth=40)
    member_id = uuid4()
    writer, session = _writer_with_results(
        [_result({"log_id": uuid4()}), _result(None), _result(None), _result(None)]
    )

    await writer.write_checkin(resolved_class, member_id, uuid4(), uuid4(), should_end=False)

    activity_params = session.execute.call_args_list[3].args[1]
    assert activity_params["activity_type"] == CLASS_ATTENDED_ACTIVITY_TYPE
    assert activity_params["m"] == str(member_id)
    assert activity_params["g"] == str(resolved_class.gym_id)
    info = json.loads(activity_params["info"])
    assert info == {
        "class_id": str(resolved_class.class_id),
        "class_name": resolved_class.class_name,
        "points": 40,
    }


async def test_null_attribution_binds_null_and_still_awards_points() -> None:
    """A no-membership staff check-in (plan_id/item_id None) binds them as SQL
    NULL on the INSERT and still awards the class's points on the new row."""
    resolved_class = _resolved_class(points_worth=60)
    member_id = uuid4()
    writer, session = _writer_with_results(
        [_result({"log_id": uuid4()}), _result(None), _result(None), _result(None)]
    )

    _, already, points = await writer.write_checkin(
        resolved_class, member_id, None, None, should_end=False
    )

    assert already is False
    assert points == 60  # points awarded despite no membership
    insert_params = session.execute.call_args_list[0].args[1]
    assert insert_params["plan_id"] is None
    assert insert_params["item_id"] is None
    # No '"None"' string slipped through — bound as real NULL.
    assert insert_params["plan_id"] != "None"


# ── writer: no points on an ON CONFLICT idempotent repeat ────────────


async def test_no_points_on_conflict() -> None:
    """An ON CONFLICT (no inserted row) awards nothing and runs no points /
    activity writes — only the insert + the existing-row read."""
    resolved_class = _resolved_class(points_worth=50)
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
        resolved_class, uuid4(), uuid4(), uuid4(), should_end=False
    )

    assert result_log_id == existing_log_id
    assert already is True
    assert points == 0
    # No award_points / insert_activity executed.
    assert session.execute.call_count == 2
