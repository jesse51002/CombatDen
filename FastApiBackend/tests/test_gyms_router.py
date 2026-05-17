"""Smoke + edge tests for the gyms router."""

from datetime import UTC, datetime
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4


def test_create_gym_returns_gym_and_owner(client, db_pool_mock, auth_headers):
    """POST /api/v1/gyms/ wires up the two-row insert and returns both."""
    gym_id = str(uuid4())
    employee_id = str(uuid4())
    user_id = str(uuid4())

    gym_row = {
        "gym_id": gym_id,
        "gym_name": "Aztec MMA",
        "gym_description": None,
        "timezone": "America/Chicago",
    }
    owner_row = {
        "employee_id": employee_id,
        "gym_id": gym_id,
        "user_id": user_id,
        "employee_type": "owner",
        "first_name": "Jesse",
        "last_name": "Musa",
        "phone": None,
        "email": "jesse@example.com",
        "employee_pic_url": None,
        "employee_public_description": None,
        "created_at": datetime.now(UTC),
    }

    session = db_pool_mock.session.return_value
    gym_result = MagicMock()
    gym_result.mappings.return_value.fetchone.return_value = gym_row
    owner_result = MagicMock()
    owner_result.mappings.return_value.fetchone.return_value = owner_row
    session.execute = AsyncMock(side_effect=[gym_result, owner_result])

    response = client.post(
        "/api/v1/gyms/",
        json={
            "gym_name": "Aztec MMA",
            "owner_first_name": "Jesse",
            "owner_last_name": "Musa",
            "owner_email": "jesse@example.com",
        },
        headers=auth_headers,
    )

    assert response.status_code == 201
    body = response.json()
    assert body["gym"]["gym_name"] == "Aztec MMA"
    assert body["owner"]["employee_type"] == "owner"


def test_get_my_gym_404_when_user_owns_no_gym(client, db_pool_mock, auth_headers):
    """GET /api/v1/gyms/me returns 404 when no gym row matches."""
    session = db_pool_mock.session.return_value
    empty = MagicMock()
    empty.mappings.return_value.fetchone.return_value = None
    session.execute = AsyncMock(return_value=empty)

    response = client.get("/api/v1/gyms/me", headers=auth_headers)
    assert response.status_code == 404


def test_update_gym_400_when_no_fields(client, auth_headers):
    """PUT /api/v1/gyms/{gym_id} returns 400 if `data` is empty."""
    response = client.put(
        f"/api/v1/gyms/{uuid4()}",
        json={"data": {}},
        headers=auth_headers,
    )
    assert response.status_code == 400
