"""Smoke + edge tests for the members router."""

from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

from tests.conftest import make_member_list_row, make_member_row


def test_create_member_returns_201(client, db_pool_mock, auth_headers, fake_gym_id):
    """POST /api/v1/members/ inserts a row and returns the response shape."""
    member_id = str(uuid4())
    db_pool_mock.execute_with_retry = AsyncMock(
        return_value=make_member_row(member_id=member_id, gym_id=fake_gym_id),
    )

    response = client.post(
        "/api/v1/members/",
        json={
            "gym_id": fake_gym_id,
            "first_name": "Ada",
            "last_name": "Lovelace",
            "email": "ada@example.com",
        },
        headers=auth_headers,
    )

    assert response.status_code == 201
    body = response.json()
    assert body["member_id"] == member_id
    assert body["points_balance"] == 100


def test_update_member_400_when_empty_data(client, auth_headers, fake_member_id):
    """PUT /api/v1/members/{member_id} rejects an empty data payload."""
    response = client.put(
        f"/api/v1/members/{fake_member_id}",
        json={"data": {}},
        headers=auth_headers,
    )
    assert response.status_code == 400


def test_list_members_returns_paginated_response(client, db_pool_mock, auth_headers, fake_gym_id):
    """POST /api/v1/members/list returns items + total."""
    member_id = str(uuid4())
    list_row = make_member_list_row(member_id=member_id, rank_id=None)
    count_row = {"total": 1}

    list_result = MagicMock()
    list_result.mappings.return_value.all.return_value = [list_row]
    count_result = MagicMock()
    count_result.mappings.return_value.fetchone.return_value = count_row

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(side_effect=[list_result, count_result])

    response = client.post(
        "/api/v1/members/list",
        json={"gym_id": fake_gym_id, "requested_view": "active"},
        headers=auth_headers,
    )

    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["member_id"] == member_id
    assert body["items"][0]["status"] == "active"
    assert body["items"][0]["current_rank"] is None


def test_list_members_hydrates_nested_rank(
    client, db_pool_mock, auth_headers, fake_gym_id, fake_rank_id
):
    """A member with a current_rank_id is returned with a nested
    current_rank object built from the joined gym_ranks columns."""
    member_id = str(uuid4())
    list_row = make_member_list_row(
        member_id=member_id,
        rank_id=fake_rank_id,
        main_name="Blue",
        sub_name="2 stripes",
        color="#1F6FEB",
        main_rank_num_order=1,
        sub_rank_num_order=2,
    )
    count_row = {"total": 1}

    list_result = MagicMock()
    list_result.mappings.return_value.all.return_value = [list_row]
    count_result = MagicMock()
    count_result.mappings.return_value.fetchone.return_value = count_row

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(side_effect=[list_result, count_result])

    response = client.post(
        "/api/v1/members/list",
        json={"gym_id": fake_gym_id},
        headers=auth_headers,
    )

    assert response.status_code == 200
    body = response.json()
    rank = body["items"][0]["current_rank"]
    assert rank is not None
    assert rank["rank_id"] == fake_rank_id
    assert rank["main_name"] == "Blue"
    assert rank["sub_name"] == "2 stripes"
    assert rank["color"] == "#1F6FEB"
    assert rank["main_rank_num_order"] == 1
    assert rank["sub_rank_num_order"] == 2


def test_total_counts_returns_per_status(client, db_pool_mock, auth_headers, fake_gym_id):
    """GET /api/v1/members/counts returns counts for each status."""
    counts_row = {
        "all_count": 10,
        "trial_count": 2,
        "active_count": 6,
        "inactive_count": 2,
    }

    result = MagicMock()
    result.mappings.return_value.fetchone.return_value = counts_row

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(return_value=result)

    response = client.get(
        f"/api/v1/members/counts?gym_id={fake_gym_id}",
        headers=auth_headers,
    )
    assert response.status_code == 200
    body = response.json()
    assert body == {"all": 10, "trial": 2, "active": 6, "inactive": 2}


def test_member_detail_includes_streak_and_redemptions(
    client, db_pool_mock, auth_headers, fake_member_id, fake_gym_id
):
    """GET /api/v1/members/{member_id} composes detail + redemptions + streak."""
    detail_row = {
        "member_id": fake_member_id,
        "gym_id": fake_gym_id,
        "first_name": "Ada",
        "last_name": "Lovelace",
        "email": "ada@example.com",
        "points_balance": 100,
        "last_class": None,
        "trial_start_date": None,
        "trial_end_date": None,
        "fully_active_start_date": None,
        "inactive_start_date": None,
        "created_at": "2026-04-01T00:00:00Z",
        "status": "inactive",
        "last_class_days_ago": None,
        "rank_rank_id": None,
        "rank_main_name": None,
        "rank_sub_name": None,
        "rank_color": None,
        "rank_image_url": None,
        "rank_main_rank_num_order": None,
        "rank_sub_rank_num_order": None,
    }

    detail_result = MagicMock()
    detail_result.mappings.return_value.fetchone.return_value = detail_row
    redemption_result = MagicMock()
    redemption_result.mappings.return_value.all.return_value = []
    streak_result = MagicMock()
    streak_result.all.return_value = []

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(
        side_effect=[detail_result, redemption_result, streak_result],
    )

    response = client.get(
        f"/api/v1/members/{fake_member_id}",
        headers=auth_headers,
    )
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "inactive"
    assert body["class_streak_weeks"] == 0
    assert body["redeemed_rewards"] == []
    assert body["current_rank"] is None


def test_member_detail_hydrates_nested_rank(
    client, db_pool_mock, auth_headers, fake_member_id, fake_gym_id, fake_rank_id
):
    """GET /api/v1/members/{id} returns a populated current_rank
    when the member has one assigned."""
    detail_row = {
        "member_id": fake_member_id,
        "gym_id": fake_gym_id,
        "first_name": "Ada",
        "last_name": "Lovelace",
        "email": "ada@example.com",
        "points_balance": 100,
        "last_class": None,
        "trial_start_date": None,
        "trial_end_date": None,
        "fully_active_start_date": None,
        "inactive_start_date": None,
        "created_at": "2026-04-01T00:00:00Z",
        "status": "active",
        "last_class_days_ago": 1,
        "rank_rank_id": fake_rank_id,
        "rank_main_name": "Purple",
        "rank_sub_name": "1 stripe",
        "rank_color": "#8957E5",
        "rank_image_url": None,
        "rank_main_rank_num_order": 2,
        "rank_sub_rank_num_order": 1,
    }

    detail_result = MagicMock()
    detail_result.mappings.return_value.fetchone.return_value = detail_row
    redemption_result = MagicMock()
    redemption_result.mappings.return_value.all.return_value = []
    streak_result = MagicMock()
    streak_result.all.return_value = []

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(
        side_effect=[detail_result, redemption_result, streak_result],
    )

    response = client.get(
        f"/api/v1/members/{fake_member_id}",
        headers=auth_headers,
    )
    assert response.status_code == 200
    body = response.json()
    rank = body["current_rank"]
    assert rank is not None
    assert rank["rank_id"] == fake_rank_id
    assert rank["main_name"] == "Purple"
    assert rank["color"] == "#8957E5"
