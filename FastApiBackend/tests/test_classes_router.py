"""Smoke + edge tests for the classes router.

The gated check-in flow runs many DB queries plus the cycle-counts service, so
these router tests override the ``checkin_service`` provider with a double and
assert the router's wiring (auth -> service -> response serialization). The
gating *logic* is unit-tested directly in
``classes/service/checkin/test_classes_checkin_plan_selector.py``.
"""

from datetime import date
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

from src.classes.schema.classes_schema import (
    CheckinMembershipBreakdown,
    CheckinResponse,
)
from src.main import app


def _override_checkin(response: CheckinResponse):
    """Override the checkin_service provider with a double returning ``response``.

    Returns the service mock; caller resets the override.
    """
    service = MagicMock()
    service.checkin = AsyncMock(return_value=response)
    app.container.checkin_service.override(service)
    return service


def test_checkin_records_when_a_plan_covers_the_class(
    client, auth_headers, fake_member_id, fake_gym_id
):
    """A covered check-in returns the log_id, chosen plan/item, and breakdown."""
    log_id = str(uuid4())
    plan_id = uuid4()
    item_id = uuid4()
    class_history_id = str(uuid4())

    response = CheckinResponse(
        log_id=log_id,
        member_id=fake_member_id,
        class_history_id=class_history_id,
        already_checked_in=False,
        chosen_plan_id=plan_id,
        chosen_item_id=item_id,
        memberships=[
            CheckinMembershipBreakdown(
                plan_id=plan_id,
                plan_type="recurring",
                class_count=None,
                classes_used=4,
                classes_remaining=None,
                is_eligible=True,
                renew_date=date(2026, 7, 1),
                end_date=None,
            )
        ],
    )
    _override_checkin(response)
    try:
        resp = client.post(
            "/api/v1/classes/checkin",
            json={
                "member_id": fake_member_id,
                "gym_id": fake_gym_id,
                "class_history_id": class_history_id,
            },
            headers=auth_headers,
        )
    finally:
        app.container.checkin_service.reset_override()

    assert resp.status_code == 200
    body = resp.json()
    assert body["log_id"] == log_id
    assert body["already_checked_in"] is False
    assert body["chosen_plan_id"] == str(plan_id)
    assert body["chosen_item_id"] == str(item_id)
    assert body["memberships"][0]["is_eligible"] is True


def test_checkin_rejected_when_no_plan_covers(
    client, auth_headers, fake_member_id, fake_gym_id
):
    """A hard-gate rejection returns 200 with null log_id and no chosen plan."""
    class_history_id = str(uuid4())
    response = CheckinResponse(
        log_id=None,
        member_id=fake_member_id,
        class_history_id=class_history_id,
        already_checked_in=False,
        chosen_plan_id=None,
        chosen_item_id=None,
        memberships=[],
    )
    _override_checkin(response)
    try:
        resp = client.post(
            "/api/v1/classes/checkin",
            json={
                "member_id": fake_member_id,
                "gym_id": fake_gym_id,
                "class_history_id": class_history_id,
            },
            headers=auth_headers,
        )
    finally:
        app.container.checkin_service.reset_override()

    assert resp.status_code == 200
    body = resp.json()
    assert body["log_id"] is None
    assert body["chosen_plan_id"] is None
    assert body["already_checked_in"] is False


def test_checkin_idempotent_returns_already_checked_in(
    client, auth_headers, fake_member_id, fake_gym_id
):
    """A duplicate check-in returns the existing log_id with already_checked_in=True."""
    log_id = str(uuid4())
    plan_id = uuid4()
    item_id = uuid4()
    class_history_id = str(uuid4())

    response = CheckinResponse(
        log_id=log_id,
        member_id=fake_member_id,
        class_history_id=class_history_id,
        already_checked_in=True,
        chosen_plan_id=plan_id,
        chosen_item_id=item_id,
        memberships=[],
    )
    _override_checkin(response)
    try:
        resp = client.post(
            "/api/v1/classes/checkin",
            json={
                "member_id": fake_member_id,
                "gym_id": fake_gym_id,
                "class_history_id": class_history_id,
            },
            headers=auth_headers,
        )
    finally:
        app.container.checkin_service.reset_override()

    assert resp.status_code == 200
    body = resp.json()
    assert body["log_id"] == log_id
    assert body["already_checked_in"] is True


def test_streak_returns_zero_when_no_attendance(
    client, db_pool_mock, auth_headers, fake_member_id, fake_gym_id
):
    """GET /api/v1/classes/streak returns 0 weeks for a never-attended member."""
    streak_result = MagicMock()
    streak_result.all.return_value = []

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(return_value=streak_result)

    response = client.get(
        f"/api/v1/classes/streak?member_id={fake_member_id}&gym_id={fake_gym_id}",
        headers=auth_headers,
    )
    assert response.status_code == 200
    body = response.json()
    assert body["class_streak_weeks"] == 0
