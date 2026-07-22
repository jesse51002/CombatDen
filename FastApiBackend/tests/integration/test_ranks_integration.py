"""Integration tests for the ranks domain.

Hits the live FastAPI backend at http://localhost:8000 via the 'api'
fixture (authorised httpx.Client for owner2).  Tests are ordered from
read-only to write+cleanup so the seed stays usable if an earlier test
fails.

Endpoints covered:
  GET  /api/v1/ranks/                   list ranks for gym (+ sub_rank_type)
  GET  /api/v1/ranks/enabled            get rank-enabled state
  GET  /api/v1/ranks/presets            flat preset list for a preset_kind
  GET  /api/v1/ranks/presets/grouped    all presets grouped by preset_kind
  POST /api/v1/ranks/                   create rank (cleaned up)
  GET  /api/v1/ranks/{rank_id}          get single rank
  PUT  /api/v1/ranks/{rank_id}          update rank (cleaned up)
  DELETE /api/v1/ranks/{rank_id}        delete rank (cleanup)
"""

from uuid import UUID, uuid4

import httpx
import pytest

from tests.integration.conftest import BACKEND_BASE_URL

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

RANKS_BASE = "/api/v1/ranks"

# Two-level model: one row per MAIN rank. A single ``name`` (no main/sub
# split, no color, no sub order); sub-ranks are a per-gym count + a
# persist-only override map, and their labels are derived at read time.
REQUIRED_RANK_FIELDS = {
    "rank_id",
    "gym_id",
    "name",
    "image_url",
    "main_rank_num_order",
    "classes_to_next_major",
    "sub_rank_count",
    "sub_rank_image_overrides",
    "created_at",
}

# The three preset kinds keyed by the ``rank_preset_kind`` enum.
PRESET_KINDS = ["bjj_belts", "bjj_belts_stripes", "flat"]

REQUIRED_RANK_PRESET_FIELDS = {
    "preset_id",
    "preset_kind",
    "main_rank_num_order",
    "name",
    "image_url",
    "classes_to_next_major",
    "sub_rank_count",
    "implied_sub_rank_type",
}


def _assert_rank_response_shape(rank: dict) -> None:
    """Assert every required field is present in a RankResponse dict."""
    missing = REQUIRED_RANK_FIELDS - set(rank.keys())
    assert not missing, f"RankResponse missing fields: {missing}"
    # The retired flat-model fields must be gone.
    for gone in ("main_name", "sub_name", "color", "sub_rank_num_order"):
        assert gone not in rank, f"RankResponse still carries retired '{gone}'"
    # rank_id and gym_id must be valid UUIDs
    UUID(rank["rank_id"])
    UUID(rank["gym_id"])
    assert isinstance(rank["name"], str) and rank["name"]
    assert isinstance(rank["main_rank_num_order"], int)
    assert isinstance(rank["classes_to_next_major"], int)
    assert isinstance(rank["sub_rank_count"], int)
    assert isinstance(rank["sub_rank_image_overrides"], dict)


# ---------------------------------------------------------------------------
# GET /api/v1/ranks/  — list ranks
# ---------------------------------------------------------------------------


class TestListRanks:
    def test_list_ranks_returns_200_with_items_key(
        self, api: httpx.Client, gym_id: str
    ) -> None:
        """GET / returns 200 with a top-level 'items' list + 'sub_rank_type'."""
        resp = api.get(RANKS_BASE + "/", params={"gym_id": gym_id})
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert "items" in body, f"'items' key missing from response: {body}"
        assert isinstance(body["items"], list)
        # The gym's per-gym sub-rank type is returned once for the whole
        # ladder so the client can derive every row's sub-rank labels.
        assert body.get("sub_rank_type") in ("stripes", "div"), body

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
            base_url=BACKEND_BASE_URL, timeout=30.0
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
    @pytest.mark.parametrize("preset_kind", PRESET_KINDS)
    def test_list_presets_returns_200_for_valid_kind(
        self, api: httpx.Client, preset_kind: str
    ) -> None:
        """GET /presets returns 200 for every valid RankPresetKind value."""
        resp = api.get(
            RANKS_BASE + "/presets", params={"preset_kind": preset_kind}
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert "items" in body
        assert isinstance(body["items"], list)

    @pytest.mark.parametrize("preset_kind", PRESET_KINDS)
    def test_list_presets_items_have_correct_shape(
        self, api: httpx.Client, preset_kind: str
    ) -> None:
        """Every preset item contains all required RankPresetResponse fields."""
        resp = api.get(
            RANKS_BASE + "/presets", params={"preset_kind": preset_kind}
        )
        assert resp.status_code == 200, resp.text
        items = resp.json()["items"]
        for preset in items:
            missing = REQUIRED_RANK_PRESET_FIELDS - set(preset.keys())
            assert not missing, f"RankPresetResponse missing fields: {missing}"
            assert preset["preset_kind"] == preset_kind
            UUID(preset["preset_id"])
            assert isinstance(preset["sub_rank_count"], int)
            # Every preset implies one of the three sub_rank_type values: a
            # stripes preset implies "stripes", while flat / plain-belt presets
            # imply "none" (the enum's own value for "sub-ranks are off", which
            # is the per-gym DB default) rather than SQL NULL.
            assert preset["implied_sub_rank_type"] in (
                None,
                "none",
                "stripes",
                "div",
            )

    def test_list_presets_invalid_kind_returns_422(
        self, api: httpx.Client
    ) -> None:
        """GET /presets with an unknown preset_kind returns 422."""
        resp = api.get(
            RANKS_BASE + "/presets", params={"preset_kind": "karate"}
        )
        assert resp.status_code == 422, resp.text

    def test_list_presets_missing_param_returns_422(
        self, api: httpx.Client
    ) -> None:
        """GET /presets without preset_kind param returns 422."""
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

    def test_presets_grouped_keys_are_valid_preset_kinds(
        self, api: httpx.Client
    ) -> None:
        """Top-level keys in 'presets' are valid RankPresetKind enum values."""
        valid_kinds = set(PRESET_KINDS)
        resp = api.get(RANKS_BASE + "/presets/grouped")
        assert resp.status_code == 200, resp.text
        keys = set(resp.json()["presets"].keys())
        assert keys <= valid_kinds, f"Unexpected keys: {keys - valid_kinds}"

    def test_presets_grouped_main_rank_shape(
        self, api: httpx.Client
    ) -> None:
        """Each grouped entry is a flat RankPresetResponse main row (one row
        per main rank; no nested sub_ranks in the two-level model)."""
        resp = api.get(RANKS_BASE + "/presets/grouped")
        assert resp.status_code == 200, resp.text
        for preset_kind, rows in resp.json()["presets"].items():
            assert isinstance(rows, list), (
                f"{preset_kind}: expected list of preset main rows"
            )
            for row in rows:
                missing = REQUIRED_RANK_PRESET_FIELDS - set(row.keys())
                assert not missing, (
                    f"{preset_kind} preset row missing: {missing}"
                )
                assert row["preset_kind"] == preset_kind
                assert isinstance(row["main_rank_num_order"], int)
                assert isinstance(row["name"], str) and row["name"]
                assert isinstance(row["sub_rank_count"], int)
                # The retired nested/flat-model fields are gone.
                for gone in ("sub_ranks", "sub_name", "color", "gym_type"):
                    assert gone not in row, f"preset row still carries '{gone}'"


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
            "name": "Integration Test Rank",
            "classes_to_next_major": 50,
            "sub_rank_count": 3,
            "image_url": "https://cdn.combatden.net/ranks/presets/white.png",
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
        assert created_rank["name"] == "Integration Test Rank"
        assert created_rank["classes_to_next_major"] == 50
        assert created_rank["sub_rank_count"] == 3
        assert created_rank["image_url"] == (
            "https://cdn.combatden.net/ranks/presets/white.png"
        )
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
        """PUT /{rank_id} returns the rank with an updated classes_to_next_major."""
        rank_id = created_rank["rank_id"]
        resp = api.put(
            f"{RANKS_BASE}/{rank_id}",
            json={"data": {"classes_to_next_major": 75}},
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        _assert_rank_response_shape(body)
        assert body["classes_to_next_major"] == 75, (
            f"Expected 75, got {body['classes_to_next_major']}"
        )

    def test_update_rank_nonexistent_returns_404(
        self, api: httpx.Client
    ) -> None:
        """PUT on an unknown rank_id returns 404."""
        resp = api.put(
            f"{RANKS_BASE}/{uuid4()}",
            json={"data": {"classes_to_next_major": 10}},
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
