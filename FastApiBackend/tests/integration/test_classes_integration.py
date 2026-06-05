"""Live integration tests for the classes domain (gated check-in + streak).

Endpoints under test:
  POST /api/v1/classes/checkin   (gated: plan eligibility + capacity + auto-end)
  GET  /api/v1/classes/streak

These run against the live backend + the seeded DB. Rather than hard-code seed
ids (which drift every reseed), the suite DISCOVERS suitable rows from the DB at
session start and skips gracefully when the DB isn't reachable / seeded. The
``api`` fixture (tests/integration/conftest.py) provides an authorised client;
``SEEDED_GYM_ID`` is the single seeded gym.
"""

from __future__ import annotations

import asyncio
from uuid import UUID, uuid4

import asyncpg
import httpx
import pytest
from dotenv import dotenv_values

from tests.seed_constants import SEEDED_GYM_ID

GYM_ID = SEEDED_GYM_ID

_ENV_PATH = "/var/home/jm/Documents/CombatDen/codebase/FastApiBackend/.env"


def _get_db_url() -> str:
    env = dotenv_values(_ENV_PATH)
    return env.get("DATABASE_URL", "").replace("postgresql+asyncpg://", "postgresql://")


def _run_async(coro):
    """Run a coroutine on a fresh loop (pytest-asyncio owns the main loop)."""
    loop = asyncio.new_event_loop()
    try:
        return loop.run_until_complete(coro)
    finally:
        loop.close()


def _delete_attendance_row(member_id: str, class_history_id: str) -> None:
    """Clean up a test-inserted attendance row so the seed is restored."""

    async def _run() -> None:
        conn = await asyncpg.connect(_get_db_url())
        try:
            await conn.execute(
                "DELETE FROM member_attendance "
                "WHERE member_id = $1 AND class_history_id = $2",
                UUID(member_id),
                UUID(class_history_id),
            )
        finally:
            await conn.close()

    _run_async(_run())


# A member with an active UNLIMITED plan eligible for a class, and a class_history
# occurrence of that class they have NOT yet attended -> a guaranteed-coverable,
# guaranteed-fresh check-in.
_FRESH_COVERED_SQL = """
SELECT ms.member_id, ch.class_history_id
FROM member_memberships_status ms
JOIN membership_plans mp
    ON mp.plan_id = ms.plan_id AND mp.gym_id = ms.gym_id
JOIN gym_classes gc
    ON gc.gym_id = ms.gym_id
    AND (gc.allowed_plan_ids IS NULL
         OR gc.allowed_plan_ids @> jsonb_build_array(ms.plan_id::text))
JOIN class_history ch
    ON ch.class_id = gc.class_id AND ch.gym_id = ms.gym_id
WHERE ms.gym_id = $1
  AND ms.status = 'active'
  AND mp.class_count IS NULL
  AND NOT EXISTS (
      SELECT 1 FROM member_attendance ma
      WHERE ma.member_id = ms.member_id
        AND ma.class_history_id = ch.class_history_id
  )
LIMIT 1
"""

# An existing attendance row -> a known-good (member, class instance) for the
# idempotency test.
_EXISTING_ATTENDANCE_SQL = """
SELECT member_id, class_history_id, log_id, plan_id, item_id
FROM member_attendance
WHERE gym_id = $1
LIMIT 1
"""

# A member at the gym with NO active membership -> the hard-gate rejection case.
_NO_MEMBERSHIP_MEMBER_SQL = """
SELECT m.member_id
FROM members m
WHERE m.gym_id = $1
  AND NOT EXISTS (
      SELECT 1 FROM member_memberships_status ms
      WHERE ms.member_id = m.member_id AND ms.status = 'active'
  )
LIMIT 1
"""

_ANY_CLASS_HISTORY_SQL = """
SELECT class_history_id FROM class_history WHERE gym_id = $1 LIMIT 1
"""


@pytest.fixture(scope="session")
def seed_ids() -> dict:
    """Discover usable ids from the live seeded DB; skip if unavailable."""

    async def _discover() -> dict:
        conn = await asyncpg.connect(_get_db_url())
        try:
            gym = UUID(GYM_ID)
            return {
                "fresh": await conn.fetchrow(_FRESH_COVERED_SQL, gym),
                "existing": await conn.fetchrow(_EXISTING_ATTENDANCE_SQL, gym),
                "no_membership": await conn.fetchrow(_NO_MEMBERSHIP_MEMBER_SQL, gym),
                "any_class": await conn.fetchrow(_ANY_CLASS_HISTORY_SQL, gym),
            }
        finally:
            await conn.close()

    try:
        return _run_async(_discover())
    except Exception as exc:  # noqa: BLE001 — any DB issue means skip, not fail
        pytest.skip(f"Seeded DB not reachable for discovery: {exc}")


# ---------------------------------------------------------------------------
# POST /api/v1/classes/checkin — 422 validation (no DB writes / no seed needed)
# ---------------------------------------------------------------------------


class TestCheckinValidation:
    """422 validation — no DB writes, no side effects."""

    def test_missing_body_returns_422(self, api: httpx.Client) -> None:
        resp = api.post("/api/v1/classes/checkin")
        assert resp.status_code == 422

    def test_missing_member_id_returns_422(self, api: httpx.Client) -> None:
        resp = api.post(
            "/api/v1/classes/checkin",
            json={"gym_id": GYM_ID, "class_history_id": str(uuid4())},
        )
        assert resp.status_code == 422

    def test_missing_gym_id_returns_422(self, api: httpx.Client) -> None:
        resp = api.post(
            "/api/v1/classes/checkin",
            json={"member_id": str(uuid4()), "class_history_id": str(uuid4())},
        )
        assert resp.status_code == 422

    def test_missing_class_history_id_returns_422(self, api: httpx.Client) -> None:
        resp = api.post(
            "/api/v1/classes/checkin",
            json={"member_id": str(uuid4()), "gym_id": GYM_ID},
        )
        assert resp.status_code == 422

    def test_invalid_uuid_returns_422(self, api: httpx.Client) -> None:
        resp = api.post(
            "/api/v1/classes/checkin",
            json={
                "member_id": "not-a-uuid",
                "gym_id": GYM_ID,
                "class_history_id": str(uuid4()),
            },
        )
        assert resp.status_code == 422


# ---------------------------------------------------------------------------
# POST /api/v1/classes/checkin — gated behavior (needs the seeded DB)
# ---------------------------------------------------------------------------


class TestGatedCheckin:
    def test_fresh_covered_checkin_records_and_attributes_a_plan(
        self, api: httpx.Client, seed_ids: dict
    ) -> None:
        """A member with a covering active plan checks in: log_id + chosen plan/item,
        already_checked_in=False, and an eligible breakdown row. Cleaned up after."""
        row = seed_ids["fresh"]
        if row is None:
            pytest.skip("No coverable, unattended (member, class) pair in seed")
        member_id = str(row["member_id"])
        class_history_id = str(row["class_history_id"])

        resp = api.post(
            "/api/v1/classes/checkin",
            json={
                "member_id": member_id,
                "gym_id": GYM_ID,
                "class_history_id": class_history_id,
            },
        )
        try:
            assert resp.status_code == 200, resp.text
            body = resp.json()
            assert body["already_checked_in"] is False
            assert body["log_id"] is not None
            UUID(body["log_id"])
            assert body["chosen_plan_id"] is not None
            assert body["chosen_item_id"] is not None
            assert any(m["is_eligible"] for m in body["memberships"])
        finally:
            _delete_attendance_row(member_id, class_history_id)

    def test_checkin_without_membership_is_hard_gated(
        self, api: httpx.Client, seed_ids: dict
    ) -> None:
        """A member with no active membership is rejected: null log_id, nothing
        written. No cleanup needed (the gate writes nothing)."""
        member_row = seed_ids["no_membership"]
        class_row = seed_ids["any_class"]
        if member_row is None or class_row is None:
            pytest.skip("No membership-less member / class_history in seed")
        member_id = str(member_row["member_id"])
        class_history_id = str(class_row["class_history_id"])

        resp = api.post(
            "/api/v1/classes/checkin",
            json={
                "member_id": member_id,
                "gym_id": GYM_ID,
                "class_history_id": class_history_id,
            },
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["log_id"] is None
        assert body["chosen_plan_id"] is None
        assert body["already_checked_in"] is False

    def test_duplicate_checkin_returns_already_checked_in(
        self, api: httpx.Client, seed_ids: dict
    ) -> None:
        """Re-posting an existing attendance returns already_checked_in=True with the
        original log_id and the stored plan/item — no new row, no capacity consumed."""
        row = seed_ids["existing"]
        if row is None:
            pytest.skip("No existing attendance row in seed")
        member_id = str(row["member_id"])
        class_history_id = str(row["class_history_id"])

        resp = api.post(
            "/api/v1/classes/checkin",
            json={
                "member_id": member_id,
                "gym_id": GYM_ID,
                "class_history_id": class_history_id,
            },
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["already_checked_in"] is True
        assert body["log_id"] == str(row["log_id"])
        assert body["chosen_plan_id"] == str(row["plan_id"])
        assert body["chosen_item_id"] == str(row["item_id"])


# ---------------------------------------------------------------------------
# GET /api/v1/classes/streak
# ---------------------------------------------------------------------------


class TestStreakValidation:
    """422 validation for GET /api/v1/classes/streak — no DB writes."""

    def test_missing_params_returns_422(self, api: httpx.Client) -> None:
        resp = api.get("/api/v1/classes/streak")
        assert resp.status_code == 422

    def test_missing_gym_id_returns_422(self, api: httpx.Client) -> None:
        resp = api.get(
            "/api/v1/classes/streak", params={"member_id": str(uuid4())}
        )
        assert resp.status_code == 422

    def test_missing_member_id_returns_422(self, api: httpx.Client) -> None:
        resp = api.get("/api/v1/classes/streak", params={"gym_id": GYM_ID})
        assert resp.status_code == 422

    def test_invalid_uuid_member_id_returns_422(self, api: httpx.Client) -> None:
        resp = api.get(
            "/api/v1/classes/streak",
            params={"member_id": "not-a-uuid", "gym_id": GYM_ID},
        )
        assert resp.status_code == 422


class TestStreakResponse:
    def test_streak_for_member_with_attendance_returns_200(
        self, api: httpx.Client, seed_ids: dict
    ) -> None:
        row = seed_ids["existing"]
        if row is None:
            pytest.skip("No attended member in seed")
        member_id = str(row["member_id"])

        resp = api.get(
            "/api/v1/classes/streak",
            params={"member_id": member_id, "gym_id": GYM_ID},
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["member_id"] == member_id
        assert isinstance(body["class_streak_weeks"], int)
        assert body["class_streak_weeks"] >= 0

    def test_streak_for_nonexistent_member_returns_404(
        self, api: httpx.Client
    ) -> None:
        """auth.verify_can_view_member 404s on an unknown member before the
        streak service runs — intentional, not a bug."""
        resp = api.get(
            "/api/v1/classes/streak",
            params={"member_id": str(uuid4()), "gym_id": GYM_ID},
        )
        assert resp.status_code == 404, resp.text
