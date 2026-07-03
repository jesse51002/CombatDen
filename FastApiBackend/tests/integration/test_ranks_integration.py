"""Integration tests for the ranks domain.

Hits the live FastAPI backend at http://localhost:8000 via the 'api'
fixture (authorised httpx.Client for owner2).  Tests are ordered from
read-only to write+cleanup so the seed stays usable if an earlier test
fails.

Endpoints covered:
  GET  /api/v1/ranks/                   list ranks for gym
  GET  /api/v1/ranks/enabled            get rank-enabled state
  GET  /api/v1/ranks/presets            flat preset list for a gym_type
  GET  /api/v1/ranks/presets/grouped    all presets grouped
  POST /api/v1/ranks/                   create rank (cleaned up)
  GET  /api/v1/ranks/{rank_id}          get single rank
  PUT  /api/v1/ranks/{rank_id}          update rank (cleaned up)
  DELETE /api/v1/ranks/{rank_id}        delete rank (cleanup)
"""

from uuid import UUID, uuid4

import httpx
import pytest

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

RANKS_BASE = "/api/v1/ranks"

REQUIRED_RANK_FIELDS = {
    "rank_id",
    "main_name",
    "sub_name",
    "color",
    "image_url",
    "main_rank_num_order",
    "sub_rank_num_order",
    "gym_id",
    "classes_till_rankup",
    "created_at",
}

REQUIRED_RANK_PRESET_FIELDS = {
    "preset_id",
    "gym_type",
    "main_rank_num_order",
    "sub_rank_num_order",
    "main_name",
    "sub_name",
    "classes_till_rankup",
    "image_url",
    "color",
}


def _assert_rank_response_shape(rank: dict) -> None:
    """Assert every required field is present in a RankResponse dict."""
    missing = REQUIRED_RANK_FIELDS - set(rank.keys())
    assert not missing, f"RankResponse missing fields: {missing}"
    # rank_id and gym_id must be valid UUIDs
    UUID(rank["rank_id"])
    UUID(rank["gym_id"])
    assert isinstance(rank["main_name"], str) and rank["main_name"]
    assert isinstance(rank["sub_name"], str) and rank["sub_name"]
    assert isinstance(rank["main_rank_num_order"], int)
    assert isinstance(rank["sub_rank_num_order"], int)
    assert isinstance(rank["classes_till_rankup"], int)


# ---------------------------------------------------------------------------
# GET /api/v1/ranks/  — list ranks
# ---------------------------------------------------------------------------


class TestListRanks:
    def test_list_ranks_returns_200_with_items_key(
        self, api: httpx.Client, gym_id: str
    ) -> None:
        """GET / returns 200 with a top-level 'items' list."""
        resp = api.get(RANKS_BASE + "/", params={"gym_id": gym_id})
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert "items" in body, f"'items' key missing from response: {body}"
        assert isinstance(body["items"], list)

    def test_list_ranks_items_have_correct_shape(
        self, api: httpx.Client, gym_id: str
    ) -> None:
        """Each item in the list matches the RankResponse schema."""
        resp = api.get(RANKS_BASE + "/", params={"gym_id": gym_id})
        assert resp.status_code == 200, resp.text
        items = resp.json()["items"]
        for rank in items:
            _assert_rank_response_shape(rank)

    def test_list_ranks_all_belong_to_gym(
        self, api: httpx.Client, gym_id: str
    ) -> None:
        """Every returned rank's gym_id matches the requested gym_id."""
        resp = api.get(RANKS_BASE + "/", params={"gym_id": gym_id})
        assert resp.status_code == 200, resp.text
        for rank in resp.json()["items"]:
            assert rank["gym_id"] == gym_id

    def test_list_ranks_requires_auth(self, gym_id: str) -> None:
        """GET / without Bearer token returns 401 or 403."""
        unauthenticated = httpx.Client(
            base_url="http://localhost:8000", timeout=30.0
        )
        resp = unauthenticated.get(RANKS_BASE + "/", params={"gym_id": gym_id})
        assert resp.status_code in (401, 403), (
            f"Expected 401/403 without auth, got {resp.status_code}"
        )
        unauthenticated.close()

    def test_list_ranks_missing_gym_id_returns_422(
        self, api: httpx.Client
    ) -> None:
        """GET / without gym_id query param returns 422 validation error."""
        resp = api.get(RANKS_BASE + "/")
        assert resp.status_code == 422, resp.text

    def test_list_ranks_unknown_gym_returns_403(
        self, api: httpx.Client
    ) -> None:
        """GET / with a gym_id the owner doesn't own returns 403."""
        unknown = str(uuid4())
        resp = api.get(RANKS_BASE + "/", params={"gym_id": unknown})
        assert resp.status_code == 403, resp.text


# ---------------------------------------------------------------------------
# GET /api/v1/ranks/enabled — get rank-enabled state
# ---------------------------------------------------------------------------


class TestGetRankEnabled:
    def test_get_rank_enabled_returns_200(
        self, api: httpx.Client, gym_id: str
    ) -> None:
        """GET /enabled returns 200 with gym_id and is_rank_enabled."""
        resp = api.get(RANKS_BASE + "/enabled", params={"gym_id": gym_id})
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert "gym_id" in body
        assert "is_rank_enabled" in body
        assert body["gym_id"] == gym_id
        assert isinstance(body["is_rank_enabled"], bool)

    def test_get_rank_enabled_unknown_gym_returns_403(
        self, api: httpx.Client
    ) -> None:
        """GET /enabled with a gym the owner doesn't own returns 403."""
        resp = api.get(
            RANKS_BASE + "/enabled", params={"gym_id": str(uuid4())}
        )
        assert resp.status_code == 403, resp.text

    def test_get_rank_enabled_missing_gym_id_returns_422(
        self, api: httpx.Client
    ) -> None:
        """GET /enabled without gym_id returns 422."""
        resp = api.get(RANKS_BASE + "/enabled")
        assert resp.status_code == 422, resp.text


# ---------------------------------------------------------------------------
# GET /api/v1/ranks/presets  — flat preset list
# ---------------------------------------------------------------------------


class TestListPresets:
    @pytest.mark.parametrize("gym_type", ["bjj", "mma", "generic"])
    def test_list_presets_returns_200_for_valid_type(
        self, api: httpx.Client, gym_type: str
    ) -> None:
        """GET /presets returns 200 for every valid GymType value."""
        resp = api.get(RANKS_BASE + "/presets", params={"gym_type": gym_type})
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert "items" in body
        assert isinstance(body["items"], list)

    @pytest.mark.parametrize("gym_type", ["bjj", "mma", "generic"])
    def test_list_presets_items_have_correct_shape(
        self, api: httpx.Client, gym_type: str
    ) -> None:
        """Every preset item contains all required RankPresetResponse fields."""
        resp = api.get(RANKS_BASE + "/presets", params={"gym_type": gym_type})
        assert resp.status_code == 200, resp.text
        items = resp.json()["items"]
        for preset in items:
            missing = REQUIRED_RANK_PRESET_FIELDS - set(preset.keys())
            assert not missing, f"RankPresetResponse missing fields: {missing}"
            assert preset["gym_type"] == gym_type
            UUID(preset["preset_id"])

    def test_list_presets_invalid_gym_type_returns_422(
        self, api: httpx.Client
    ) -> None:
        """GET /presets with an unknown gym_type returns 422."""
        resp = api.get(
            RANKS_BASE + "/presets", params={"gym_type": "karate"}
        )
        assert resp.status_code == 422, resp.text

    def test_list_presets_missing_param_returns_422(
        self, api: httpx.Client
    ) -> None:
        """GET /presets without gym_type param returns 422."""
        resp = api.get(RANKS_BASE + "/presets")
        assert resp.status_code == 422, resp.text


# ---------------------------------------------------------------------------
# GET /api/v1/ranks/presets/grouped  — all presets grouped
# ---------------------------------------------------------------------------


class TestPresetsGrouped:
    def test_presets_grouped_returns_200(self, api: httpx.Client) -> None:
        """GET /presets/grouped returns 200 with a 'presets' dict."""
        resp = api.get(RANKS_BASE + "/presets/grouped")
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert "presets" in body
        assert isinstance(body["presets"], dict)

    def test_presets_grouped_keys_are_valid_gym_types(
        self, api: httpx.Client
    ) -> None:
        """Top-level keys in 'presets' are valid GymType enum values."""
        valid_types = {"bjj", "mma", "generic"}
        resp = api.get(RANKS_BASE + "/presets/grouped")
        assert resp.status_code == 200, resp.text
        keys = set(resp.json()["presets"].keys())
        assert keys <= valid_types, f"Unexpected keys: {keys - valid_types}"

    def test_presets_grouped_main_rank_shape(
        self, api: httpx.Client
    ) -> None:
        """Each grouped entry has main_rank_num_order, main_name, sub_ranks."""
        resp = api.get(RANKS_BASE + "/presets/grouped")
        assert resp.status_code == 200, resp.text
        for gym_type, groups in resp.json()["presets"].items():
            assert isinstance(groups, list), (
                f"{gym_type}: expected list of groups"
            )
            for group in groups:
                assert "main_rank_num_order" in group, group
                assert "main_name" in group, group
                assert "sub_ranks" in group, group
                assert isinstance(group["sub_ranks"], list)

    def test_presets_grouped_sub_rank_shape(self, api: httpx.Client) -> None:
        """Each sub-rank has preset_id, sub_rank_num_order, sub_name, etc."""
        required_sub = {
            "preset_id",
            "sub_rank_num_order",
            "sub_name",
            "classes_till_rankup",
            "image_url",
            "color",
        }
        resp = api.get(RANKS_BASE + "/presets/grouped")
        assert resp.status_code == 200, resp.text
        for gym_type, groups in resp.json()["presets"].items():
            for group in groups:
                for sub in group["sub_ranks"]:
                    missing = required_sub - set(sub.keys())
                    assert not missing, (
                        f"{gym_type}/{group['main_name']} sub_rank missing: {missing}"
                    )


# ---------------------------------------------------------------------------
# Create / Get / Update / Delete round-trip (write with cleanup)
# ---------------------------------------------------------------------------


class TestRankCRUDRoundTrip:
    """Create a rank, read/update it, then delete it so seed stays clean."""

    @pytest.fixture(scope="class")
    def created_rank(self, api: httpx.Client, gym_id: str) -> dict:
        """POST a test rank and yield its response dict; delete on teardown."""
        payload = {
            "gym_id": gym_id,
            "main_rank_num_order": 999,
            "sub_rank_num_order": 999,
            "main_name": "Integration Test Main",
            "sub_name": "Integration Test Sub",
            "classes_till_rankup": 50,
            "color": "#ABCDEF",
        }
        resp = api.post(RANKS_BASE + "/", json=payload)
        assert resp.status_code == 201, (
            f"Create rank failed: {resp.status_code} {resp.text}"
        )
        rank = resp.json()
        yield rank
        # Cleanup: delete the rank even if tests failed.
        rank_id = rank.get("rank_id")
        if rank_id:
            api.delete(f"{RANKS_BASE}/{rank_id}")

    def test_create_rank_response_shape(self, created_rank: dict) -> None:
        """POST / returns a fully-shaped RankResponse."""
        _assert_rank_response_shape(created_rank)

    def test_create_rank_fields_match_payload(
        self, created_rank: dict, gym_id: str
    ) -> None:
        """Created rank echoes back the fields we sent."""
        assert created_rank["main_rank_num_order"] == 999
        assert created_rank["sub_rank_num_order"] == 999
        assert created_rank["main_name"] == "Integration Test Main"
        assert created_rank["sub_name"] == "Integration Test Sub"
        assert created_rank["classes_till_rankup"] == 50
        assert created_rank["color"] == "#ABCDEF"
        assert created_rank["gym_id"] == gym_id

    def test_get_rank_by_id(
        self, api: httpx.Client, created_rank: dict
    ) -> None:
        """GET /{rank_id} returns the same rank that was just created."""
        rank_id = created_rank["rank_id"]
        resp = api.get(f"{RANKS_BASE}/{rank_id}")
        assert resp.status_code == 200, resp.text
        body = resp.json()
        _assert_rank_response_shape(body)
        assert body["rank_id"] == rank_id

    def test_get_rank_nonexistent_returns_404(
        self, api: httpx.Client
    ) -> None:
        """GET /{rank_id} with an unknown UUID returns 404."""
        resp = api.get(f"{RANKS_BASE}/{uuid4()}")
        assert resp.status_code == 404, resp.text

    def test_update_rank(
        self, api: httpx.Client, created_rank: dict
    ) -> None:
        """PUT /{rank_id} returns updated rank with new classes_till_rankup."""
        rank_id = created_rank["rank_id"]
        resp = api.put(
            f"{RANKS_BASE}/{rank_id}",
            json={"data": {"classes_till_rankup": 75}},
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        _assert_rank_response_shape(body)
        assert body["classes_till_rankup"] == 75, (
            f"Expected 75, got {body['classes_till_rankup']}"
        )

    def test_update_rank_nonexistent_returns_404(
        self, api: httpx.Client
    ) -> None:
        """PUT on an unknown rank_id returns 404."""
        resp = api.put(
            f"{RANKS_BASE}/{uuid4()}",
            json={"data": {"classes_till_rankup": 10}},
        )
        assert resp.status_code == 404, resp.text

    def test_delete_rank(
        self, api: httpx.Client, created_rank: dict
    ) -> None:
        """DELETE /{rank_id} returns 204 and rank is gone afterward."""
        rank_id = created_rank["rank_id"]
        # Guard: if update test already deleted it, skip (unlikely but safe).
        resp = api.delete(f"{RANKS_BASE}/{rank_id}")
        assert resp.status_code == 204, resp.text
        # Confirm it's gone.
        get_resp = api.get(f"{RANKS_BASE}/{rank_id}")
        assert get_resp.status_code == 404, (
            f"Rank still accessible after delete: {get_resp.status_code}"
        )
        # Patch created_rank so the fixture teardown no-ops cleanly.
        created_rank["rank_id"] = None  # type: ignore[index]

    def test_delete_rank_nonexistent_returns_404(
        self, api: httpx.Client
    ) -> None:
        """DELETE on an unknown rank_id returns 404."""
        resp = api.delete(f"{RANKS_BASE}/{uuid4()}")
        assert resp.status_code == 404, resp.text
