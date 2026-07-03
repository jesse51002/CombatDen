"""Integration tests for the rewards domain.

Hits the live FastAPI backend at http://localhost:8000.
Covers read-only endpoints only:
  - GET /api/v1/rewards/          (list rewards for gym)
  - GET /api/v1/rewards/{id}      (fetch single reward)

Does NOT call redeem (POST /{id}/redeem) — that mutates points_balance.

Prerequisites:
  - ``uvicorn src.main:app --reload`` running on port 8000.
  - Local Supabase stack (``supabase start``) up and seeded.

Run with:
    poetry run pytest tests/integration/test_rewards_integration.py -v
"""

import httpx
import pytest

# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------

REWARDS_BASE = "/api/v1/rewards/"


def _assert_reward_shape(item: dict) -> None:
    """Assert a single RewardResponse has all required fields with correct types."""
    required_uuid_fields = {"reward_id", "gym_id"}
    # price_label / image_url are NOT NULL on gym_rewards (writers fill
    # platform defaults when omitted), so RewardResponse types both as
    # required str, never null.
    required_str_fields = {"title", "price_label", "image_url"}
    required_int_fields = {"point_cost"}
    required_bool_fields = {"is_active"}
    required_nullable_str_fields: set[str] = set()
    required_datetime_fields = {"created_at"}

    for field in required_uuid_fields:
        assert field in item, f"Missing field: {field}"
        assert isinstance(item[field], str) and len(item[field]) == 36, (
            f"{field} is not a valid UUID string: {item[field]!r}"
        )

    for field in required_str_fields:
        assert field in item, f"Missing field: {field}"
        assert isinstance(item[field], str), f"{field} should be str, got {type(item[field])}"

    for field in required_int_fields:
        assert field in item, f"Missing field: {field}"
        assert isinstance(item[field], int), f"{field} should be int, got {type(item[field])}"
        assert item[field] > 0, f"{field} must be > 0, got {item[field]}"

    for field in required_bool_fields:
        assert field in item, f"Missing field: {field}"
        assert isinstance(item[field], bool), (
            f"{field} should be bool, got {type(item[field])}"
        )

    for field in required_nullable_str_fields:
        assert field in item, f"Missing field: {field}"
        assert item[field] is None or isinstance(item[field], str), (
            f"{field} should be str or null, got {type(item[field])}"
        )

    for field in required_datetime_fields:
        assert field in item, f"Missing field: {field}"
        assert isinstance(item[field], str) and len(item[field]) > 0, (
            f"{field} should be a non-empty datetime string, got {item[field]!r}"
        )


# ---------------------------------------------------------------------------
# GET /api/v1/rewards/  — list rewards
# ---------------------------------------------------------------------------


class TestListRewards:
    """Tests for GET /api/v1/rewards/?gym_id=<id>."""

    def test_list_rewards_returns_200(self, api: httpx.Client, gym_id: str) -> None:
        """GET /api/v1/rewards/ with a valid gym_id returns HTTP 200."""
        response = api.get(REWARDS_BASE, params={"gym_id": gym_id})
        assert response.status_code == 200, (
            f"Expected 200, got {response.status_code}: {response.text}"
        )

    def test_list_rewards_response_has_items_key(
        self, api: httpx.Client, gym_id: str
    ) -> None:
        """Response body is a JSON object with an 'items' array (RewardListResponse)."""
        response = api.get(REWARDS_BASE, params={"gym_id": gym_id})
        assert response.status_code == 200
        data = response.json()
        assert "items" in data, f"'items' key missing from response: {data}"
        assert isinstance(data["items"], list), (
            f"'items' should be a list, got {type(data['items'])}"
        )

    def test_list_rewards_items_have_correct_shape(
        self, api: httpx.Client, gym_id: str
    ) -> None:
        """Each item in 'items' matches the RewardResponse schema."""
        response = api.get(REWARDS_BASE, params={"gym_id": gym_id})
        assert response.status_code == 200
        data = response.json()
        items = data["items"]
        # Seeded gym must have at least one reward
        assert len(items) > 0, (
            "Expected at least one reward in seed data, got empty list"
        )
        for item in items:
            _assert_reward_shape(item)

    def test_list_rewards_all_belong_to_gym(
        self, api: httpx.Client, gym_id: str
    ) -> None:
        """Every returned reward has gym_id matching the requested gym."""
        response = api.get(REWARDS_BASE, params={"gym_id": gym_id})
        assert response.status_code == 200
        data = response.json()
        for item in data["items"]:
            assert item["gym_id"] == gym_id, (
                f"Reward {item['reward_id']} has gym_id {item['gym_id']!r}, "
                f"expected {gym_id!r}"
            )

    def test_list_rewards_default_excludes_inactive(
        self, api: httpx.Client, gym_id: str
    ) -> None:
        """Without include_inactive=true, all returned rewards are active."""
        response = api.get(REWARDS_BASE, params={"gym_id": gym_id})
        assert response.status_code == 200
        data = response.json()
        for item in data["items"]:
            assert item["is_active"] is True, (
                f"Inactive reward {item['reward_id']} returned without include_inactive"
            )

    def test_list_rewards_ordered_by_point_cost_asc(
        self, api: httpx.Client, gym_id: str
    ) -> None:
        """Active rewards are ordered by point_cost ascending (per SQL ORDER BY)."""
        response = api.get(REWARDS_BASE, params={"gym_id": gym_id})
        assert response.status_code == 200
        items = response.json()["items"]
        if len(items) < 2:
            pytest.skip("Need at least 2 rewards to verify ordering")
        costs = [item["point_cost"] for item in items]
        assert costs == sorted(costs), (
            f"Rewards not ordered by point_cost ASC: {costs}"
        )

    def test_list_rewards_include_inactive_true(
        self, api: httpx.Client, gym_id: str
    ) -> None:
        """include_inactive=true returns 200 and a valid response shape."""
        response = api.get(
            REWARDS_BASE, params={"gym_id": gym_id, "include_inactive": "true"}
        )
        assert response.status_code == 200, (
            f"Expected 200 with include_inactive=true, got {response.status_code}: {response.text}"
        )
        data = response.json()
        assert "items" in data
        for item in data["items"]:
            _assert_reward_shape(item)

    def test_list_rewards_requires_auth(self, gym_id: str) -> None:
        """GET /api/v1/rewards/ without a token returns 401 or 403."""
        unauthenticated = httpx.Client(base_url="http://localhost:8000", timeout=30.0)
        try:
            response = unauthenticated.get(REWARDS_BASE, params={"gym_id": gym_id})
            assert response.status_code in (401, 403), (
                f"Expected 401/403 without auth, got {response.status_code}"
            )
        finally:
            unauthenticated.close()

    def test_list_rewards_missing_gym_id_returns_422(
        self, api: httpx.Client
    ) -> None:
        """GET /api/v1/rewards/ without gym_id returns 422 (missing required param)."""
        response = api.get(REWARDS_BASE)
        assert response.status_code == 422, (
            f"Expected 422 for missing gym_id, got {response.status_code}: {response.text}"
        )

    def test_list_rewards_invalid_gym_id_returns_422(
        self, api: httpx.Client
    ) -> None:
        """GET /api/v1/rewards/ with a non-UUID gym_id returns 422."""
        response = api.get(REWARDS_BASE, params={"gym_id": "not-a-uuid"})
        assert response.status_code == 422, (
            f"Expected 422 for invalid UUID, got {response.status_code}: {response.text}"
        )

    def test_list_rewards_unknown_gym_returns_403_or_empty(
        self, api: httpx.Client
    ) -> None:
        """GET /api/v1/rewards/ for a gym the owner doesn't own returns 403 or empty list."""
        unknown_gym = "00000000-0000-0000-0000-000000000001"
        response = api.get(REWARDS_BASE, params={"gym_id": unknown_gym})
        # Either forbidden (403) or authorized but empty (200 + [])
        assert response.status_code in (200, 403), (
            f"Unexpected status {response.status_code}: {response.text}"
        )
        if response.status_code == 200:
            # If 200, items must be empty (different owner's gym)
            data = response.json()
            assert data["items"] == [], (
                f"Expected empty items for unknown gym, got: {data['items']}"
            )


# ---------------------------------------------------------------------------
# GET /api/v1/rewards/{reward_id}  — fetch single reward
# ---------------------------------------------------------------------------


class TestGetReward:
    """Tests for GET /api/v1/rewards/{reward_id}."""

    @pytest.fixture(scope="class")
    def a_reward_id(self, api: httpx.Client, gym_id: str) -> str:
        """Return the reward_id of the first active reward for our gym."""
        response = api.get(REWARDS_BASE, params={"gym_id": gym_id})
        assert response.status_code == 200
        items = response.json()["items"]
        assert items, "No rewards seeded for this gym — cannot run get-reward tests"
        return str(items[0]["reward_id"])

    def test_get_reward_returns_200(
        self, api: httpx.Client, gym_id: str, a_reward_id: str
    ) -> None:
        """GET /api/v1/rewards/{reward_id} returns HTTP 200."""
        response = api.get(f"{REWARDS_BASE}{a_reward_id}")
        assert response.status_code == 200, (
            f"Expected 200, got {response.status_code}: {response.text}"
        )

    def test_get_reward_response_shape(
        self, api: httpx.Client, gym_id: str, a_reward_id: str
    ) -> None:
        """GET single reward returns a well-formed RewardResponse."""
        response = api.get(f"{REWARDS_BASE}{a_reward_id}")
        assert response.status_code == 200
        data = response.json()
        _assert_reward_shape(data)

    def test_get_reward_id_matches_path(
        self, api: httpx.Client, gym_id: str, a_reward_id: str
    ) -> None:
        """The returned reward_id matches the path parameter."""
        response = api.get(f"{REWARDS_BASE}{a_reward_id}")
        assert response.status_code == 200
        data = response.json()
        assert data["reward_id"] == a_reward_id, (
            f"reward_id in response {data['reward_id']!r} != path {a_reward_id!r}"
        )

    def test_get_reward_gym_id_matches(
        self, api: httpx.Client, gym_id: str, a_reward_id: str
    ) -> None:
        """The returned reward's gym_id matches the authenticated owner's gym."""
        response = api.get(f"{REWARDS_BASE}{a_reward_id}")
        assert response.status_code == 200
        data = response.json()
        assert data["gym_id"] == gym_id, (
            f"reward gym_id {data['gym_id']!r} != expected {gym_id!r}"
        )

    def test_get_reward_not_found_returns_404(
        self, api: httpx.Client, gym_id: str
    ) -> None:
        """GET /api/v1/rewards/{id} for a non-existent UUID returns 404."""
        nonexistent = "00000000-0000-0000-0000-000000000099"
        response = api.get(f"{REWARDS_BASE}{nonexistent}")
        assert response.status_code == 404, (
            f"Expected 404 for unknown reward_id, got {response.status_code}: {response.text}"
        )

    def test_get_reward_invalid_uuid_returns_422(
        self, api: httpx.Client, gym_id: str
    ) -> None:
        """GET /api/v1/rewards/not-a-uuid returns 422 (path param validation)."""
        response = api.get(f"{REWARDS_BASE}not-a-uuid")
        assert response.status_code == 422, (
            f"Expected 422 for invalid UUID path param, "
            f"got {response.status_code}: {response.text}"
        )

    def test_get_reward_requires_auth(self, a_reward_id: str) -> None:
        """GET /api/v1/rewards/{id} without a token returns 401 or 403."""
        unauthenticated = httpx.Client(base_url="http://localhost:8000", timeout=30.0)
        try:
            response = unauthenticated.get(f"{REWARDS_BASE}{a_reward_id}")
            assert response.status_code in (401, 403), (
                f"Expected 401/403 without auth, got {response.status_code}"
            )
        finally:
            unauthenticated.close()
