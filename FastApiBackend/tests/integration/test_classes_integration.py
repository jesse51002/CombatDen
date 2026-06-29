"""Live integration tests for the classes domain (Phase-4 gated check-in).

Endpoints under test:
  POST /api/v1/classes/checkin   (class_id + occurrence_date; lazy materialize,
                                  plan gate + room capacity + points + override)
  GET  /api/v1/classes/streak

These run against the live backend + the seeded DB. Rather than hard-code seed
ids (which drift every reseed), the suite DISCOVERS suitable rows from the DB at
session start and skips gracefully when the DB isn't reachable / seeded. The
``api`` fixture (tests/integration/conftest.py) provides an authorised client;
``SEEDED_GYM_ID`` is the single seeded gym.

NOTE: the Phase-1 migration (``uq_class_history_occurrence`` UNIQUE) must be
applied for the lazy materializer's ON CONFLICT to work. Until then the gated
check-in tests fail at the materialize step — that is expected and is a missing
migration, not a code defect.
"""

from __future__ import annotations

import asyncio
from datetime import date, timedelta
from uuid import UUID, uuid4

import asyncpg
import httpx
import pytest
from dotenv import dotenv_values

from tests.seed_constants import SEEDED_GYM_ID

GYM_ID = SEEDED_GYM_ID

_ENV_PATH = "/var/home/jm/Documents/CombatDen/codebase/FastApiBackend/.env"
# How far ahead to scan the schedule board for a usable occurrence.
_BOARD_WINDOW_DAYS = 45


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


# One covering member (active UNLIMITED plan, eligible) per active, non-deleted
# class. The check-in materializes class_history lazily, so NO pre-existing
# class_history row is required -- the occurrence_date comes from the schedule
# board (the expander), not from seeded history.
_COVERING_BY_CLASS_SQL = """
SELECT DISTINCT ON (gc.class_id)
    gc.class_id,
    ms.member_id,
    gc.points_worth
FROM member_memberships_status ms
JOIN membership_plans mp
    ON mp.plan_id = ms.plan_id AND mp.gym_id = ms.gym_id
JOIN gym_classes gc
    ON gc.gym_id = ms.gym_id
    AND gc.is_deleted = FALSE
    AND gc.is_active = TRUE
    AND (gc.allowed_plan_ids IS NULL
         OR gc.allowed_plan_ids @> jsonb_build_array(ms.plan_id::text))
WHERE ms.gym_id = $1
  AND ms.status = 'active'
  AND mp.class_count IS NULL
ORDER BY gc.class_id, ms.member_id
"""

# An existing attendance row -> a member with attendance, for the streak test.
_EXISTING_ATTENDANCE_SQL = """
SELECT member_id, class_history_id, log_id, plan_id, item_id
FROM member_attendance
WHERE gym_id = $1
LIMIT 1
"""

# A member at the gym with NO active membership -> the no-membership skip case.
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


def _covered_target(api: httpx.Client, covering: dict[str, dict]) -> dict | None:
    """Intersect the schedule board with covering members -> a check-in target.

    Returns the first non-cancelled board occurrence whose class has a covering
    member, as ``{member_id, class_id, points_worth, occurrence_date}``.
    """
    today = date.today()
    resp = api.get(
        "/api/v1/classes/instances",
        params={
            "gym_id": GYM_ID,
            "start_date": today.isoformat(),
            "end_date": (today + timedelta(days=_BOARD_WINDOW_DAYS)).isoformat(),
        },
    )
    if resp.status_code != 200:
        return None
    for occ in resp.json()["items"]:
        if occ["is_cancelled"]:
            continue
        cover = covering.get(occ["class_id"])
        if cover is None:
            continue
        return {
            "member_id": cover["member_id"],
            "class_id": occ["class_id"],
            "points_worth": cover["points_worth"],
            "occurrence_date": occ["class_date"],
        }
    return None


@pytest.fixture(scope="session")
def seed_ids(api: httpx.Client) -> dict:
    """Discover usable ids from the live seeded DB + board; skip if unavailable."""

    async def _discover() -> dict:
        conn = await asyncpg.connect(_get_db_url())
        try:
            gym = UUID(GYM_ID)
            covering_rows = await conn.fetch(_COVERING_BY_CLASS_SQL, gym)
            covering = {
                str(r["class_id"]): {
                    "member_id": str(r["member_id"]),
                    "points_worth": int(r["points_worth"]),
                }
                for r in covering_rows
            }
            return {
                "covering": covering,
                "existing": await conn.fetchrow(_EXISTING_ATTENDANCE_SQL, gym),
                "no_membership": await conn.fetchrow(_NO_MEMBERSHIP_MEMBER_SQL, gym),
            }
        finally:
            await conn.close()

    try:
        ids = _run_async(_discover())
    except Exception as exc:  # noqa: BLE001 — any DB issue means skip, not fail
        pytest.skip(f"Seeded DB not reachable for discovery: {exc}")
    ids["covered"] = _covered_target(api, ids["covering"])
    return ids


def _member_points(member_id: str) -> int:
    async def _run() -> int:
        conn = await asyncpg.connect(_get_db_url())
        try:
            return await conn.fetchval(
                "SELECT points_balance FROM members WHERE member_id = $1",
                UUID(member_id),
            )
        finally:
            await conn.close()

    return _run_async(_run())


def _class_attended_activity_ids(member_id: str, class_id: str) -> set[UUID]:
    async def _run() -> set[UUID]:
        conn = await asyncpg.connect(_get_db_url())
        try:
            rows = await conn.fetch(
                "SELECT activity_id FROM member_activities "
                "WHERE member_id = $1 AND activity_type = 'class_attended' "
                "AND activity_info->>'class_id' = $2",
                UUID(member_id),
                class_id,
            )
            return {r["activity_id"] for r in rows}
        finally:
            await conn.close()

    return _run_async(_run())


def _teardown_checkin(
    member_id: str,
    class_history_id: str,
    new_activity_ids: set[UUID],
    restore_points: int,
) -> None:
    """Undo a test check-in: delete the attendance + the (lazily created)
    class_history row + the new class_attended activities, restore points."""

    async def _run() -> None:
        conn = await asyncpg.connect(_get_db_url())
        try:
            await conn.execute(
                "DELETE FROM member_attendance "
                "WHERE member_id = $1 AND class_history_id = $2",
                UUID(member_id),
                UUID(class_history_id),
            )
            if new_activity_ids:
                await conn.execute(
                    "DELETE FROM member_activities WHERE activity_id = ANY($1)",
                    list(new_activity_ids),
                )
            # The materializer creates a fresh class_history row (its gym-tz UTC
            # occurred_at differs from the seed's naive stamp), so delete it.
            await conn.execute(
                "DELETE FROM class_history WHERE class_history_id = $1",
                UUID(class_history_id),
            )
            await conn.execute(
                "UPDATE members SET points_balance = $2 WHERE member_id = $1",
                UUID(member_id),
                restore_points,
            )
        finally:
            await conn.close()

    _run_async(_run())


# ---------------------------------------------------------------------------
# POST /api/v1/classes/checkin — 422 validation (no DB writes / no seed needed)
# ---------------------------------------------------------------------------


class TestCheckinValidation:
    """422 validation for the new (class_id + occurrence_date) body shape."""

    def test_missing_body_returns_422(self, api: httpx.Client) -> None:
        resp = api.post("/api/v1/classes/checkin")
        assert resp.status_code == 422

    def test_missing_member_id_returns_422(self, api: httpx.Client) -> None:
        resp = api.post(
            "/api/v1/classes/checkin",
            json={
                "gym_id": GYM_ID,
                "class_id": str(uuid4()),
                "occurrence_date": "2026-06-01",
            },
        )
        assert resp.status_code == 422

    def test_missing_class_id_returns_422(self, api: httpx.Client) -> None:
        resp = api.post(
            "/api/v1/classes/checkin",
            json={
                "member_id": str(uuid4()),
                "gym_id": GYM_ID,
                "occurrence_date": "2026-06-01",
            },
        )
        assert resp.status_code == 422

    def test_missing_occurrence_date_returns_422(self, api: httpx.Client) -> None:
        resp = api.post(
            "/api/v1/classes/checkin",
            json={
                "member_id": str(uuid4()),
                "gym_id": GYM_ID,
                "class_id": str(uuid4()),
            },
        )
        assert resp.status_code == 422

    def test_invalid_uuid_returns_422(self, api: httpx.Client) -> None:
        resp = api.post(
            "/api/v1/classes/checkin",
            json={
                "member_id": "not-a-uuid",
                "gym_id": GYM_ID,
                "class_id": str(uuid4()),
                "occurrence_date": "2026-06-01",
            },
        )
        assert resp.status_code == 422

    def test_invalid_date_returns_422(self, api: httpx.Client) -> None:
        resp = api.post(
            "/api/v1/classes/checkin",
            json={
                "member_id": str(uuid4()),
                "gym_id": GYM_ID,
                "class_id": str(uuid4()),
                "occurrence_date": "not-a-date",
            },
        )
        assert resp.status_code == 422


# ---------------------------------------------------------------------------
# POST /api/v1/classes/checkin — gated behavior (needs the seeded DB + the
# uq_class_history_occurrence migration for the materializer's ON CONFLICT)
# ---------------------------------------------------------------------------


class TestGatedCheckin:
    def test_fresh_checkin_records_awards_points_and_logs_activity(
        self, api: httpx.Client, seed_ids: dict
    ) -> None:
        """A covered check-in records attendance, awards exactly the class's
        points_worth (balance rises by it), and writes ONE class_attended
        activity. Fully cleaned up after."""
        row = seed_ids["covered"]
        if row is None:
            pytest.skip("No board occurrence for a coverable class in seed")
        member_id = row["member_id"]
        class_id = row["class_id"]
        points_worth = row["points_worth"]
        occurrence_date = row["occurrence_date"]

        before_points = _member_points(member_id)
        before_activities = _class_attended_activity_ids(member_id, class_id)

        resp = api.post(
            "/api/v1/classes/checkin",
            json={
                "member_id": member_id,
                "gym_id": GYM_ID,
                "class_id": class_id,
                "occurrence_date": occurrence_date,
            },
        )
        body = resp.json()
        class_history_id = body.get("class_history_id")
        after_activities = _class_attended_activity_ids(member_id, class_id)
        new_activity_ids = after_activities - before_activities
        try:
            assert resp.status_code == 200, resp.text
            assert body["already_checked_in"] is False
            assert body["log_id"] is not None
            UUID(body["log_id"])
            assert body["chosen_plan_id"] is not None
            assert body["chosen_item_id"] is not None
            assert body["points_awarded"] == points_worth
            assert _member_points(member_id) == before_points + points_worth
            assert len(new_activity_ids) == 1
        finally:
            if class_history_id:
                _teardown_checkin(
                    member_id, class_history_id, new_activity_ids, before_points
                )

    def test_duplicate_checkin_is_idempotent_and_awards_no_extra_points(
        self, api: httpx.Client, seed_ids: dict
    ) -> None:
        """A second check-in for the same (member, occurrence) is idempotent:
        already_checked_in=True, points_awarded=0, balance unchanged."""
        row = seed_ids["covered"]
        if row is None:
            pytest.skip("No board occurrence for a coverable class in seed")
        member_id = row["member_id"]
        class_id = row["class_id"]
        occurrence_date = row["occurrence_date"]
        payload = {
            "member_id": member_id,
            "gym_id": GYM_ID,
            "class_id": class_id,
            "occurrence_date": occurrence_date,
        }

        before_points = _member_points(member_id)
        before_activities = _class_attended_activity_ids(member_id, class_id)

        first = api.post("/api/v1/classes/checkin", json=payload)
        class_history_id = first.json().get("class_history_id")
        try:
            assert first.status_code == 200, first.text
            after_first_points = _member_points(member_id)

            second = api.post("/api/v1/classes/checkin", json=payload)
            assert second.status_code == 200, second.text
            body = second.json()
            assert body["already_checked_in"] is True
            assert body["points_awarded"] == 0
            # No extra points on the repeat.
            assert _member_points(member_id) == after_first_points
        finally:
            after_activities = _class_attended_activity_ids(member_id, class_id)
            if class_history_id:
                _teardown_checkin(
                    member_id,
                    class_history_id,
                    after_activities - before_activities,
                    before_points,
                )

    def test_checkin_without_membership_is_skipped(
        self, api: httpx.Client, seed_ids: dict
    ) -> None:
        """A member with no active membership is skipped: null log_id,
        skip_reason=no_membership, nothing written (no cleanup needed)."""
        covered = seed_ids["covered"]
        member_row = seed_ids["no_membership"]
        if covered is None or member_row is None:
            pytest.skip("No membership-less member / coverable class in seed")
        member_id = str(member_row["member_id"])
        class_id = covered["class_id"]
        occurrence_date = covered["occurrence_date"]

        resp = api.post(
            "/api/v1/classes/checkin",
            json={
                "member_id": member_id,
                "gym_id": GYM_ID,
                "class_id": class_id,
                "occurrence_date": occurrence_date,
            },
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["log_id"] is None
        assert body["chosen_plan_id"] is None
        assert body["already_checked_in"] is False
        assert body["points_awarded"] == 0
        assert body["skip_reason"] == "no_membership"


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
