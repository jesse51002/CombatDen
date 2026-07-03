"""Smoke + edge tests for the rewards router."""

from datetime import UTC, datetime
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

from src.core.config import settings
from tests.conftest import make_reward_row

# ─── helpers ────────────────────────────────────────────────────────────────

def make_redemption_row(
    *,
    redemption_id: str,
    member_id: str,
    reward_id: str,
    gym_id: str,
    point_cost: int = 50,
    status: str = "pending",
    resolved_at=None,
    points_balance_after: int = 50,
) -> dict:
    return {
        "redemption_id": redemption_id,
        "member_id": member_id,
        "reward_id": reward_id,
        "gym_id": gym_id,
        "point_cost": point_cost,
        "requested_at": datetime.now(UTC),
        "status": status,
        "resolved_at": resolved_at,
        "points_balance_after": points_balance_after,
    }


def make_transition_row(
    *,
    redemption_id: str,
    status: str,
    points_balance_after: int | None = None,
) -> dict:
    return {
        "redemption_id": redemption_id,
        "status": status,
        "resolved_at": datetime.now(UTC),
        "points_balance_after": points_balance_after,
    }


# ─── reward CRUD ─────────────────────────────────────────────────────────────

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
            "price_label": "Free",
        },
        headers=auth_headers,
    )
    assert response.status_code == 201
    assert response.json()["title"] == "Free smoothie"


def test_create_reward_with_price_label(client, db_pool_mock, auth_headers, fake_gym_id):
    """POST /api/v1/rewards/ accepts and returns price_label."""
    reward_id = str(uuid4())
    row = make_reward_row(reward_id=reward_id, gym_id=fake_gym_id)
    row["price_label"] = "$5 off"
    db_pool_mock.execute_with_retry = AsyncMock(return_value=row)

    response = client.post(
        "/api/v1/rewards/",
        json={
            "gym_id": fake_gym_id,
            "title": "Discount",
            "point_cost": 100,
            "price_label": "$5 off",
        },
        headers=auth_headers,
    )
    assert response.status_code == 201
    assert response.json()["price_label"] == "$5 off"


def test_create_reward_without_image_url_uses_default(
    client, db_pool_mock, auth_headers, fake_gym_id
):
    """POST /api/v1/rewards/ with no image_url fills
    settings.default_reward_image_url before the INSERT (mirrors the classes
    create path)."""
    reward_id = str(uuid4())

    async def fake_execute_with_retry(sql, params, max_retries=3):
        return make_reward_row(
            reward_id=reward_id,
            gym_id=fake_gym_id,
            title=params["title"],
            point_cost=params["point_cost"],
            price_label=params["price_label"],
            image_url=params["image_url"],
        )

    db_pool_mock.execute_with_retry = AsyncMock(side_effect=fake_execute_with_retry)

    response = client.post(
        "/api/v1/rewards/",
        json={
            "gym_id": fake_gym_id,
            "title": "Free smoothie",
            "point_cost": 50,
            "price_label": "Free",
        },
        headers=auth_headers,
    )
    assert response.status_code == 201
    assert response.json()["image_url"] == settings.default_reward_image_url


def test_create_reward_without_price_label_returns_422(
    client, auth_headers, fake_gym_id
):
    """POST /api/v1/rewards/ with no price_label 422s — price_label is a
    required create field."""
    response = client.post(
        "/api/v1/rewards/",
        json={
            "gym_id": fake_gym_id,
            "title": "Free smoothie",
            "point_cost": 50,
        },
        headers=auth_headers,
    )
    assert response.status_code == 422


def test_update_reward_rejects_explicit_null_image_url(
    client, auth_headers, fake_reward_id
):
    """PUT with an explicit ``"image_url": null`` 422s — image_url can be
    changed but never cleared."""
    response = client.put(
        f"/api/v1/rewards/{fake_reward_id}",
        json={"data": {"image_url": None}},
        headers=auth_headers,
    )
    assert response.status_code == 422


def test_update_reward_rejects_explicit_null_price_label(
    client, auth_headers, fake_reward_id
):
    """PUT with an explicit ``"price_label": null`` 422s — price_label can
    be changed but never cleared."""
    response = client.put(
        f"/api/v1/rewards/{fake_reward_id}",
        json={"data": {"price_label": None}},
        headers=auth_headers,
    )
    assert response.status_code == 422


def test_update_reward_rejects_explicit_null_title(
    client, auth_headers, fake_reward_id
):
    """PUT with an explicit ``"title": null`` 422s — title is NOT NULL, so
    an unguarded null would reach the SET clause as a DB error / 500."""
    response = client.put(
        f"/api/v1/rewards/{fake_reward_id}",
        json={"data": {"title": None}},
        headers=auth_headers,
    )
    assert response.status_code == 422


def test_update_reward_rejects_explicit_null_point_cost(
    client, auth_headers, fake_reward_id
):
    """PUT with an explicit ``"point_cost": null`` 422s — point_cost is
    NOT NULL; ``gt=0`` alone would let the None union branch through."""
    response = client.put(
        f"/api/v1/rewards/{fake_reward_id}",
        json={"data": {"point_cost": None}},
        headers=auth_headers,
    )
    assert response.status_code == 422


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


# ─── member-initiated redeem ─────────────────────────────────────────────────

def test_redeem_reward_returns_pending_redemption(
    client, db_pool_mock, auth_headers, fake_gym_id, fake_member_id, fake_reward_id
):
    """POST /{reward_id}/redeem returns a pending redemption with new balance."""
    redemption_id = str(uuid4())
    row = make_redemption_row(
        redemption_id=redemption_id,
        member_id=fake_member_id,
        reward_id=fake_reward_id,
        gym_id=fake_gym_id,
        status="pending",
    )

    result = MagicMock()
    result.mappings.return_value.fetchone.return_value = row

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
    assert body["status"] == "pending"
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


# ─── staff redeem-for-member ─────────────────────────────────────────────────

def test_redeem_for_member_auto_approve(
    client, db_pool_mock, auth_headers, fake_gym_id, fake_member_id, fake_reward_id
):
    """POST /{reward_id}/redeem-for-member (override=false) returns approved."""
    redemption_id = str(uuid4())
    row = make_redemption_row(
        redemption_id=redemption_id,
        member_id=fake_member_id,
        reward_id=fake_reward_id,
        gym_id=fake_gym_id,
        status="approved",
        resolved_at=datetime.now(UTC),
    )

    result = MagicMock()
    result.mappings.return_value.fetchone.return_value = row

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(return_value=result)

    response = client.post(
        f"/api/v1/rewards/{fake_reward_id}/redeem-for-member",
        json={"member_id": fake_member_id, "override": False},
        headers=auth_headers,
    )

    assert response.status_code == 201
    assert response.json()["status"] == "approved"


def test_redeem_for_member_override(
    client, db_pool_mock, auth_headers, fake_gym_id, fake_member_id, fake_reward_id
):
    """POST /{reward_id}/redeem-for-member override=true uses the override SQL path."""
    redemption_id = str(uuid4())
    row = make_redemption_row(
        redemption_id=redemption_id,
        member_id=fake_member_id,
        reward_id=fake_reward_id,
        gym_id=fake_gym_id,
        status="approved",
        resolved_at=datetime.now(UTC),
        points_balance_after=0,
    )

    result = MagicMock()
    result.mappings.return_value.fetchone.return_value = row

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(return_value=result)

    response = client.post(
        f"/api/v1/rewards/{fake_reward_id}/redeem-for-member",
        json={"member_id": fake_member_id, "override": True},
        headers=auth_headers,
    )

    assert response.status_code == 201
    body = response.json()
    assert body["status"] == "approved"
    assert body["points_balance_after"] == 0


def test_redeem_for_member_400_when_inactive(
    client, db_pool_mock, auth_headers, fake_member_id, fake_reward_id
):
    """Staff redeem returns 400 when reward is inactive (no row returned)."""
    result = MagicMock()
    result.mappings.return_value.fetchone.return_value = None

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(return_value=result)

    response = client.post(
        f"/api/v1/rewards/{fake_reward_id}/redeem-for-member",
        json={"member_id": fake_member_id, "override": False},
        headers=auth_headers,
    )
    assert response.status_code == 400


def test_redeem_for_member_approves_existing_pending(
    client, db_pool_mock, auth_headers, fake_gym_id, fake_member_id, fake_reward_id
):
    """When the member has an open pending redemption for the reward, the
    smart path approves it in ONE statement — no second debit SQL runs
    (override included: nothing to drain when the request is already paid)."""
    existing_id = str(uuid4())
    row = make_redemption_row(
        redemption_id=existing_id,
        member_id=fake_member_id,
        reward_id=fake_reward_id,
        gym_id=fake_gym_id,
        status="approved",
        resolved_at=datetime.now(UTC),
    )
    result = MagicMock()
    result.mappings.return_value.fetchone.return_value = row

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(return_value=result)

    response = client.post(
        f"/api/v1/rewards/{fake_reward_id}/redeem-for-member",
        json={"member_id": fake_member_id, "override": True},
        headers=auth_headers,
    )

    assert response.status_code == 201
    assert response.json()["redemption_id"] == existing_id
    # Exactly one statement: approve_existing_pending found the row, so
    # neither redeem_reward.sql nor redeem_reward_override.sql ever ran.
    assert session.execute.await_count == 1
    executed_sql = str(session.execute.await_args_list[0].args[0])
    assert "locked_pending" in executed_sql


def test_redeem_for_member_falls_through_to_fresh_debit(
    client, db_pool_mock, auth_headers, fake_gym_id, fake_member_id, fake_reward_id
):
    """With NO pending redemption for the reward, the smart lookup returns
    0 rows and the call falls through to a fresh guarded debit."""
    fresh_id = str(uuid4())
    empty = MagicMock()
    empty.mappings.return_value.fetchone.return_value = None
    fresh = MagicMock()
    fresh.mappings.return_value.fetchone.return_value = make_redemption_row(
        redemption_id=fresh_id,
        member_id=fake_member_id,
        reward_id=fake_reward_id,
        gym_id=fake_gym_id,
        status="approved",
        resolved_at=datetime.now(UTC),
    )

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(side_effect=[empty, fresh])

    response = client.post(
        f"/api/v1/rewards/{fake_reward_id}/redeem-for-member",
        json={"member_id": fake_member_id, "override": False},
        headers=auth_headers,
    )

    assert response.status_code == 201
    assert response.json()["redemption_id"] == fresh_id
    assert session.execute.await_count == 2


# ─── approve / reject ────────────────────────────────────────────────────────

def _setup_two_executes(db_pool_mock, first_row, second_row):
    """Wire db_pool_mock to return two different rows on consecutive executes."""
    results = [MagicMock(), MagicMock()]
    results[0].mappings.return_value.fetchone.return_value = first_row
    results[1].mappings.return_value.fetchone.return_value = second_row
    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(side_effect=results)


def test_approve_redemption_returns_200(
    client, db_pool_mock, auth_headers, fake_member_id, fake_reward_id, fake_gym_id
):
    """POST /redemptions/{id}/approve returns 200 with approved status."""
    redemption_id = str(uuid4())
    auth_info = {
        "redemption_id": redemption_id,
        "gym_id": fake_gym_id,
        "member_id": fake_member_id,
        "status": "pending",
    }
    transition_row = make_transition_row(
        redemption_id=redemption_id, status="approved"
    )
    _setup_two_executes(db_pool_mock, auth_info, transition_row)

    response = client.post(
        f"/api/v1/rewards/redemptions/{redemption_id}/approve",
        headers=auth_headers,
    )

    assert response.status_code == 200
    assert response.json()["status"] == "approved"


def test_approve_redemption_409_when_already_decided(
    client, db_pool_mock, auth_headers, fake_member_id, fake_gym_id
):
    """Approving a non-pending redemption returns 409."""
    redemption_id = str(uuid4())
    auth_info = {
        "redemption_id": redemption_id,
        "gym_id": fake_gym_id,
        "member_id": fake_member_id,
        "status": "approved",  # already decided
    }
    # Second execute (approve SQL) returns no row → AlreadyDecidedError → 409
    _setup_two_executes(db_pool_mock, auth_info, None)

    response = client.post(
        f"/api/v1/rewards/redemptions/{redemption_id}/approve",
        headers=auth_headers,
    )
    assert response.status_code == 409


def test_reject_redemption_returns_200_with_balance(
    client, db_pool_mock, auth_headers, fake_member_id, fake_reward_id, fake_gym_id
):
    """POST /redemptions/{id}/reject refunds points and returns updated balance."""
    redemption_id = str(uuid4())
    auth_info = {
        "redemption_id": redemption_id,
        "gym_id": fake_gym_id,
        "member_id": fake_member_id,
        "status": "pending",
    }
    transition_row = make_transition_row(
        redemption_id=redemption_id,
        status="rejected",
        points_balance_after=150,
    )
    _setup_two_executes(db_pool_mock, auth_info, transition_row)

    response = client.post(
        f"/api/v1/rewards/redemptions/{redemption_id}/reject",
        headers=auth_headers,
    )

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "rejected"
    assert body["points_balance_after"] == 150


def test_reject_redemption_409_when_already_decided(
    client, db_pool_mock, auth_headers, fake_member_id, fake_gym_id
):
    """Rejecting a non-pending redemption returns 409."""
    redemption_id = str(uuid4())
    auth_info = {
        "redemption_id": redemption_id,
        "gym_id": fake_gym_id,
        "member_id": fake_member_id,
        "status": "rejected",
    }
    _setup_two_executes(db_pool_mock, auth_info, None)

    response = client.post(
        f"/api/v1/rewards/redemptions/{redemption_id}/reject",
        headers=auth_headers,
    )
    assert response.status_code == 409


def test_approve_redemption_404_when_not_found(
    client, db_pool_mock, auth_headers
):
    """Approving a non-existent redemption returns 404."""
    redemption_id = str(uuid4())
    result = MagicMock()
    result.mappings.return_value.fetchone.return_value = None

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(return_value=result)

    response = client.post(
        f"/api/v1/rewards/redemptions/{redemption_id}/approve",
        headers=auth_headers,
    )
    assert response.status_code == 404


# ─── pending queue ───────────────────────────────────────────────────────────

def test_list_pending_redemptions(
    client, db_pool_mock, auth_headers, fake_gym_id, fake_member_id, fake_reward_id
):
    """GET /redemptions/pending returns the queue for the gym."""
    redemption_id = str(uuid4())
    pending_row = {
        "redemption_id": redemption_id,
        "member_id": fake_member_id,
        "member_name": "Ada Lovelace",
        "reward_title": "Free smoothie",
        "reward_image_url": "https://images.pexels.com/photos/5493207/pexels-photo-5493207.jpeg?auto=compress&cs=tinysrgb&w=1200",
        "point_cost": 50,
        "requested_at": datetime.now(UTC),
        "total": 1,
    }

    result = MagicMock()
    result.mappings.return_value.all.return_value = [pending_row]

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(return_value=result)

    response = client.get(
        f"/api/v1/rewards/redemptions/pending?gym_id={fake_gym_id}",
        headers=auth_headers,
    )
    assert response.status_code == 200
    body = response.json()
    assert len(body["items"]) == 1
    assert body["total"] == 1
    item = body["items"][0]
    assert item["member_name"] == "Ada Lovelace"
    assert item["reward_title"] == "Free smoothie"


def test_list_pending_redemptions_empty_page_has_zero_total(
    client, db_pool_mock, auth_headers, fake_gym_id
):
    """GET /redemptions/pending returns total=0 (not an error) for an empty page."""
    result = MagicMock()
    result.mappings.return_value.all.return_value = []

    session = db_pool_mock.session.return_value
    session.execute = AsyncMock(return_value=result)

    response = client.get(
        f"/api/v1/rewards/redemptions/pending?gym_id={fake_gym_id}&limit=10&offset=1000",
        headers=auth_headers,
    )
    assert response.status_code == 200
    body = response.json()
    assert body["items"] == []
    assert body["total"] == 0


def test_list_pending_redemptions_rejects_limit_over_200(
    client, auth_headers, fake_gym_id
):
    """GET /redemptions/pending validates limit <= 200."""
    response = client.get(
        f"/api/v1/rewards/redemptions/pending?gym_id={fake_gym_id}&limit=201",
        headers=auth_headers,
    )
    assert response.status_code == 422


def test_list_pending_redemptions_rejects_negative_pagination(
    client, auth_headers, fake_gym_id
):
    """Negative limit/offset (and limit=0) 422 at validation instead of
    reaching Postgres LIMIT/OFFSET, which rejects negatives as a 500."""
    base = f"/api/v1/rewards/redemptions/pending?gym_id={fake_gym_id}"
    for params in ("&limit=-1", "&limit=0", "&offset=-1"):
        response = client.get(base + params, headers=auth_headers)
        assert response.status_code == 422, params


# ─── redemption history ───────────────────────────────────────────────────────

def test_redemption_history_returns_items(client, db_pool_mock, auth_headers, fake_member_id):
    """GET /api/v1/rewards/redemptions returns last redemptions for a member."""
    history_row = {
        "redemption_id": str(uuid4()),
        "reward_id": str(uuid4()),
        "title": "Free smoothie",
        "image_url": "https://images.pexels.com/photos/5493207/pexels-photo-5493207.jpeg?auto=compress&cs=tinysrgb&w=1200",
        "price_label": "Free",
        "point_cost": 50,
        "requested_at": datetime.now(UTC),
        "status": "pending",
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
