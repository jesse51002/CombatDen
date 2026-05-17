"""Smoke + edge tests for the classes router."""

from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4


def test_checkin_inserts_attendance_and_bumps_last_class(
    client, db_pool_mock, auth_headers, fake_member_id, fake_gym_id
):
    """POST /api/v1/classes/checkin returns log_id + already_checked_in=False."""
    log_id = str(uuid4())
    class_history_id = str(uuid4())

    insert_result = MagicMock()
    insert_result.mappings.return_value.fetchone.return_value = {"log_id": log_id}
    update_result = MagicMock()

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(side_effect=[insert_result, update_result])

    response = client.post(
        "/api/v1/classes/checkin",
        json={
            "member_id": fake_member_id,
            "gym_id": fake_gym_id,
            "class_history_id": class_history_id,
        },
        headers=auth_headers,
    )

    assert response.status_code == 200
    body = response.json()
    assert body["log_id"] == log_id
    assert body["already_checked_in"] is False


def test_checkin_idempotent_returns_already_checked_in(
    client, db_pool_mock, auth_headers, fake_member_id, fake_gym_id
):
    """A duplicate check-in returns the existing log_id with already_checked_in=True."""
    log_id = str(uuid4())
    class_history_id = str(uuid4())

    insert_result = MagicMock()
    insert_result.mappings.return_value.fetchone.return_value = None
    existing_result = MagicMock()
    existing_result.mappings.return_value.fetchone.return_value = {"log_id": log_id}
    update_result = MagicMock()

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(
        side_effect=[insert_result, existing_result, update_result],
    )

    response = client.post(
        "/api/v1/classes/checkin",
        json={
            "member_id": fake_member_id,
            "gym_id": fake_gym_id,
            "class_history_id": class_history_id,
        },
        headers=auth_headers,
    )

    assert response.status_code == 200
    body = response.json()
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
