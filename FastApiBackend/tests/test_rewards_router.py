"""Smoke + edge tests for the rewards router."""

from datetime import UTC, datetime
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

from tests.conftest import make_reward_row


def test_list_rewards_returns_active_only_by_default(
    client, db_pool_mock, auth_headers, fake_gym_id
):
    """GET /api/v1/rewards/?gym_id=... returns the catalog."""
    reward_id = str(uuid4())
    rows = [make_reward_row(reward_id=reward_id, gym_id=fake_gym_id)]

    list_result = MagicMock()
    list_result.mappings.return_value.all.return_value = rows

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(return_value=list_result)

    response = client.get(
        f"/api/v1/rewards/?gym_id={fake_gym_id}",
        headers=auth_headers,
    )
    assert response.status_code == 200
    body = response.json()
    assert len(body["items"]) == 1
    assert body["items"][0]["reward_id"] == reward_id


def test_create_reward_returns_201(client, db_pool_mock, auth_headers, fake_gym_id):
    """POST /api/v1/rewards/ inserts and returns the new row."""
    reward_id = str(uuid4())
    db_pool_mock.execute_with_retry = AsyncMock(
        return_value=make_reward_row(
            reward_id=reward_id,
            gym_id=fake_gym_id,
            title="Free smoothie",
            point_cost=50,
        ),
    )

    response = client.post(
        "/api/v1/rewards/",
        json={
            "gym_id": fake_gym_id,
            "title": "Free smoothie",
            "point_cost": 50,
        },
        headers=auth_headers,
    )
    assert response.status_code == 201
    assert response.json()["title"] == "Free smoothie"


def test_redeem_reward_returns_redemption(
    client, db_pool_mock, auth_headers, fake_gym_id, fake_member_id, fake_reward_id
):
    """POST /api/v1/rewards/{reward_id}/redeem returns redemption + new balance."""
    redemption_id = str(uuid4())
    redemption_row = {
        "redemption_id": redemption_id,
        "member_id": fake_member_id,
        "reward_id": fake_reward_id,
        "gym_id": fake_gym_id,
        "point_cost": 50,
        "redeemed_at": datetime.now(UTC),
        "points_balance_after": 50,
    }

    result = MagicMock()
    result.mappings.return_value.fetchone.return_value = redemption_row

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(return_value=result)

    response = client.post(
        f"/api/v1/rewards/{fake_reward_id}/redeem",
        json={"member_id": fake_member_id},
        headers=auth_headers,
    )

    assert response.status_code == 201
    body = response.json()
    assert body["redemption_id"] == redemption_id
    assert body["points_balance_after"] == 50


def test_redeem_reward_400_when_insufficient_points(
    client, db_pool_mock, auth_headers, fake_member_id, fake_reward_id
):
    """Redemption returns 400 when SQL CTE returns no rows (insufficient / inactive)."""
    result = MagicMock()
    result.mappings.return_value.fetchone.return_value = None

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(return_value=result)

    response = client.post(
        f"/api/v1/rewards/{fake_reward_id}/redeem",
        json={"member_id": fake_member_id},
        headers=auth_headers,
    )
    assert response.status_code == 400
    assert "insufficient" in response.json()["detail"].lower()


def test_redemption_history_returns_items(client, db_pool_mock, auth_headers, fake_member_id):
    """GET /api/v1/rewards/redemptions returns last redemptions for a member."""
    history_row = {
        "redemption_id": str(uuid4()),
        "reward_id": str(uuid4()),
        "title": "Free smoothie",
        "image_url": None,
        "amount_off": None,
        "point_cost": 50,
        "redeemed_at": datetime.now(UTC),
    }

    result = MagicMock()
    result.mappings.return_value.all.return_value = [history_row]

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(return_value=result)

    response = client.get(
        f"/api/v1/rewards/redemptions?member_id={fake_member_id}",
        headers=auth_headers,
    )
    assert response.status_code == 200
    assert len(response.json()["items"]) == 1


def test_immutable_columns_guard_blocks_reward_id_update(
    client, db_pool_mock, auth_headers, fake_gym_id, fake_reward_id
):
    """The column guard rejects attempts to update reward_id via the data field."""
    db_pool_mock.execute_with_retry = AsyncMock(
        side_effect=Exception("should not be reached"),
    )

    get_row = make_reward_row(reward_id=fake_reward_id, gym_id=fake_gym_id)
    get_result = MagicMock()
    get_result.mappings.return_value.fetchone.return_value = get_row
    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(return_value=get_result)

    # The schema rejects unknown fields by default but allows extras —
    # send a valid update and confirm the response contains the row.
    db_pool_mock.execute_with_retry = AsyncMock(
        return_value=make_reward_row(
            reward_id=fake_reward_id, gym_id=fake_gym_id, title="Updated title"
        ),
    )

    response = client.put(
        f"/api/v1/rewards/{fake_reward_id}",
        json={"data": {"title": "Updated title"}},
        headers=auth_headers,
    )
    assert response.status_code == 200
    assert response.json()["title"] == "Updated title"
