"""Live integration tests for the classes domain.

Endpoints under test:
  POST /api/v1/classes/checkin
  GET  /api/v1/classes/streak

Seed constants (gym_id = 21636369-8b52-9b4a-97b7-50923ceb3ffd / owner1@test.com):
NOTE: the member_id / class_history_id values below are from an older seed and
are still stale — only the gym_id has been re-pointed to the current seed.
  - Tanya  member_id = 1afa89ea-e596-4cfa-a333-6efd691dcf5a  (no existing attendance)
  - Stephanie member_id = 90156040-208c-4209-816b-b4766c937acc (has existing attendance)
  - Existing attendance row: member=Stephanie, class_history_id=87687e3e-6813-4d14-8d3b-bdbb03416d67
  - Free class_history_id (no Tanya attendance): 0d17055c-1f5b-433b-a6ab-4a5a0b32fe70

Safety rules:
  - The fresh checkin test is idempotent by the contract: a duplicate call returns
    already_checked_in=True.  We call it once and then clean up via direct DB DELETE
    so the seed is restored.  (The DB fixture helper does the teardown.)
  - We never DELETE existing attendance rows — they are pre-seeded and must not change.
"""

from __future__ import annotations

import asyncio
from uuid import UUID, uuid4

import asyncpg
import httpx
from dotenv import dotenv_values

from tests.seed_constants import SEEDED_GYM_ID

# ---------------------------------------------------------------------------
# Seed constants
# ---------------------------------------------------------------------------

GYM_ID = SEEDED_GYM_ID

# Stephanie — has pre-seeded attendance rows
MEMBER_WITH_ATTENDANCE = "90156040-208c-4209-816b-b4766c937acc"
EXISTING_CLASS_HISTORY_ID = "87687e3e-6813-4d14-8d3b-bdbb03416d67"
EXISTING_LOG_ID = "96d5e7ee-8582-4939-bf0d-88a994b45238"

# Tanya — no attendance rows at start of suite; we use one fresh class_history_id
# that belongs to this gym but has no attendance for Tanya.
MEMBER_NO_ATTENDANCE = "1afa89ea-e596-4cfa-a333-6efd691dcf5a"
FREE_CLASS_HISTORY_ID = "0d17055c-1f5b-433b-a6ab-4a5a0b32fe70"

# ---------------------------------------------------------------------------
# DB teardown helper
# ---------------------------------------------------------------------------

_ENV_PATH = "/var/home/jm/Documents/CombatDen/codebase/FastApiBackend/.env"


def _get_db_url() -> str:
    env = dotenv_values(_ENV_PATH)
    return env.get("DATABASE_URL", "").replace("postgresql+asyncpg://", "postgresql://")


def _delete_attendance_row(member_id: str, class_history_id: str) -> None:
    """Synchronous wrapper to clean up a test-inserted attendance row.

    Creates a fresh event loop because pytest-asyncio (AUTO mode) manages
    its own loop and asyncio.get_event_loop() raises RuntimeError in the
    main thread after that loop has been set up.
    """

    async def _run() -> None:
        conn = await asyncpg.connect(_get_db_url())
        await conn.execute(
            "DELETE FROM member_attendance WHERE member_id = $1 AND class_history_id = $2",
            UUID(member_id),
            UUID(class_history_id),
        )
        await conn.close()

    loop = asyncio.new_event_loop()
    try:
        loop.run_until_complete(_run())
    finally:
        loop.close()


# ---------------------------------------------------------------------------
# POST /api/v1/classes/checkin
# ---------------------------------------------------------------------------


class TestCheckinValidation:
    """422 validation — no DB writes, no side effects."""

    def test_missing_body_returns_422(self, api: httpx.Client) -> None:
        """POST with no body at all must return 422."""
        resp = api.post("/api/v1/classes/checkin")
        assert resp.status_code == 422

    def test_missing_member_id_returns_422(self, api: httpx.Client) -> None:
        """Body missing member_id must return 422."""
        resp = api.post(
            "/api/v1/classes/checkin",
            json={
                "gym_id": GYM_ID,
                "class_history_id": str(uuid4()),
            },
        )
        assert resp.status_code == 422

    def test_missing_gym_id_returns_422(self, api: httpx.Client) -> None:
        """Body missing gym_id must return 422."""
        resp = api.post(
            "/api/v1/classes/checkin",
            json={
                "member_id": MEMBER_WITH_ATTENDANCE,
                "class_history_id": str(uuid4()),
            },
        )
        assert resp.status_code == 422

    def test_missing_class_history_id_returns_422(self, api: httpx.Client) -> None:
        """Body missing class_history_id must return 422."""
        resp = api.post(
            "/api/v1/classes/checkin",
            json={
                "member_id": MEMBER_WITH_ATTENDANCE,
                "gym_id": GYM_ID,
            },
        )
        assert resp.status_code == 422

    def test_invalid_uuid_returns_422(self, api: httpx.Client) -> None:
        """Non-UUID strings in UUID fields must return 422."""
        resp = api.post(
            "/api/v1/classes/checkin",
            json={
                "member_id": "not-a-uuid",
                "gym_id": GYM_ID,
                "class_history_id": str(uuid4()),
            },
        )
        assert resp.status_code == 422


class TestCheckinIdempotency:
    """POST to a (member, class_history) pair that already exists must return
    already_checked_in=True and the original log_id without creating a new row.
    This test is safe — it only reads an existing seeded row, never writes."""

    def test_duplicate_checkin_returns_already_checked_in(
        self, api: httpx.Client
    ) -> None:
        """Re-checking in the same (member, class_history) pair returns 200 with
        already_checked_in=True and the original log_id."""
        resp = api.post(
            "/api/v1/classes/checkin",
            json={
                "member_id": MEMBER_WITH_ATTENDANCE,
                "gym_id": GYM_ID,
                "class_history_id": EXISTING_CLASS_HISTORY_ID,
            },
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()

        # Shape check
        assert "log_id" in body
        assert "member_id" in body
        assert "class_history_id" in body
        assert "already_checked_in" in body

        # Idempotency semantics
        assert body["already_checked_in"] is True
        assert body["log_id"] == EXISTING_LOG_ID
        assert body["member_id"] == MEMBER_WITH_ATTENDANCE
        assert body["class_history_id"] == EXISTING_CLASS_HISTORY_ID


class TestCheckinFreshWrite:
    """POST for a (member, class_history) pair that does NOT yet exist.
    After the call we immediately clean up the inserted row so the seed
    is left in its original state."""

    def test_fresh_checkin_returns_200_with_correct_shape(
        self, api: httpx.Client
    ) -> None:
        """A new (member, class_history) pair returns 200,
        already_checked_in=False, and a valid UUID log_id."""
        resp = api.post(
            "/api/v1/classes/checkin",
            json={
                "member_id": MEMBER_NO_ATTENDANCE,
                "gym_id": GYM_ID,
                "class_history_id": FREE_CLASS_HISTORY_ID,
            },
        )
        try:
            assert resp.status_code == 200, resp.text
            body = resp.json()

            # Shape
            assert "log_id" in body
            assert "member_id" in body
            assert "class_history_id" in body
            assert "already_checked_in" in body

            # Values
            assert body["already_checked_in"] is False
            assert body["member_id"] == MEMBER_NO_ATTENDANCE
            assert body["class_history_id"] == FREE_CLASS_HISTORY_ID
            # log_id must be a valid UUID
            UUID(body["log_id"])
        finally:
            # Always clean up regardless of assertion outcome
            _delete_attendance_row(MEMBER_NO_ATTENDANCE, FREE_CLASS_HISTORY_ID)


# ---------------------------------------------------------------------------
# GET /api/v1/classes/streak
# ---------------------------------------------------------------------------


class TestStreakValidation:
    """422 validation for GET /api/v1/classes/streak — no DB writes."""

    def test_missing_params_returns_422(self, api: httpx.Client) -> None:
        """GET with no query params must return 422."""
        resp = api.get("/api/v1/classes/streak")
        assert resp.status_code == 422

    def test_missing_gym_id_returns_422(self, api: httpx.Client) -> None:
        """GET with only member_id (no gym_id) must return 422."""
        resp = api.get(
            "/api/v1/classes/streak",
            params={"member_id": MEMBER_WITH_ATTENDANCE},
        )
        assert resp.status_code == 422

    def test_missing_member_id_returns_422(self, api: httpx.Client) -> None:
        """GET with only gym_id (no member_id) must return 422."""
        resp = api.get(
            "/api/v1/classes/streak",
            params={"gym_id": GYM_ID},
        )
        assert resp.status_code == 422

    def test_invalid_uuid_member_id_returns_422(self, api: httpx.Client) -> None:
        """Non-UUID member_id must return 422."""
        resp = api.get(
            "/api/v1/classes/streak",
            params={"member_id": "not-a-uuid", "gym_id": GYM_ID},
        )
        assert resp.status_code == 422


class TestStreakResponse:
    """Happy-path GET /api/v1/classes/streak tests."""

    def test_streak_for_member_with_attendance_returns_200(
        self, api: httpx.Client
    ) -> None:
        """Member with pre-seeded attendance records returns 200 with correct schema."""
        resp = api.get(
            "/api/v1/classes/streak",
            params={
                "member_id": MEMBER_WITH_ATTENDANCE,
                "gym_id": GYM_ID,
            },
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()

        # Schema shape matches StreakResponse
        assert "member_id" in body
        assert "class_streak_weeks" in body

        # Values
        assert body["member_id"] == MEMBER_WITH_ATTENDANCE
        assert isinstance(body["class_streak_weeks"], int)
        assert body["class_streak_weeks"] >= 0

    def test_streak_for_member_no_attendance_returns_zero(
        self, api: httpx.Client
    ) -> None:
        """Member with no attendance records must return class_streak_weeks=0."""
        resp = api.get(
            "/api/v1/classes/streak",
            params={
                "member_id": MEMBER_NO_ATTENDANCE,
                "gym_id": GYM_ID,
            },
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()

        assert body["member_id"] == MEMBER_NO_ATTENDANCE
        assert body["class_streak_weeks"] == 0

    def test_streak_for_nonexistent_member_returns_404(
        self, api: httpx.Client
    ) -> None:
        """A member_id that doesn't exist in the DB should return 404.

        auth.verify_can_view_member does a DB lookup on the member_id and
        returns 404 "Member not found" before the streak service is ever
        called — this is intentional, not a bug.
        """
        nonexistent = str(uuid4())
        resp = api.get(
            "/api/v1/classes/streak",
            params={
                "member_id": nonexistent,
                "gym_id": GYM_ID,
            },
        )
        assert resp.status_code == 404, (
            f"Expected 404 for unknown member_id, got {resp.status_code}: {resp.text}"
        )
