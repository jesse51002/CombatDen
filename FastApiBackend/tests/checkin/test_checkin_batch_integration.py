"""Live integration tests for the batch staff check-in (Phase 4b).

Endpoint under test:
  POST /api/v1/classes/{class_id}/occurrences/{occurrence_date}/checkin-batch

Same live-discovery approach as test_classes_integration.py: rather than
hard-code seed ids (which drift every reseed), the suite DISCOVERS a class with
>= 2 covering members (active UNLIMITED eligible plan), a board occurrence for
it, and a membership-less member, then exercises a mixed batch + an idempotent
re-post. It cleans up EXACTLY what it creates (attendance + lazily-created
class_history + new class_attended activities) and restores each member's
points_balance.

NOTE: the Phase-1 migration (``uq_class_history_occurrence`` UNIQUE) is NOT
applied to the shared test DB, so ``resolve_occurrence``'s lazy materialize
(``INSERT ... ON CONFLICT ON CONSTRAINT uq_class_history_occurrence``) raises a
Postgres ``42704 undefined_object`` BEFORE any per-member work. The router maps
that to **500** ("Failed to record batch check-in"), so these tests fail at the
first POST (expecting 207, getting 500). That is the documented migration block,
not a code defect.

The ``all_failed -> 500`` status mapping is covered deterministically (no DB) in
``tests/test_classes_router.py::test_batch_checkin_total_failure_returns_500``.
It is intentionally NOT asserted here: under the migration block every POST
returns 500 from the generic handler, so a 500 assertion in this file would pass
for the WRONG reason (the migration, not all_failed) — exactly the kind of
write-around the FastApiBackend rules forbid.
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

# Covering members (active UNLIMITED eligible plan) for each active, non-deleted
# class. Grouped in Python to find a class with >= 2 distinct covering members,
# so one batch can yield a fresh check-in AND an already-checked-in member.
_COVERING_MEMBERS_SQL = """
SELECT gc.class_id, ms.member_id, gc.points_worth
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


def _get_db_url() -> str:
    env = dotenv_values(_ENV_PATH)
    return env.get("DATABASE_URL", "").replace(
        "postgresql+asyncpg://", "postgresql://"
    )


def _run_async(coro):
    """Run a coroutine on a fresh loop (pytest-asyncio owns the main loop)."""
    loop = asyncio.new_event_loop()
    try:
        return loop.run_until_complete(coro)
    finally:
        loop.close()


def _multi_covered_target(
    api: httpx.Client, by_class: dict[str, list[dict]]
) -> dict | None:
    """Intersect the board with classes that have >= 2 covering members.

    Returns the first non-cancelled board occurrence whose class has two or more
    covering members, as
    ``{class_id, occurrence_date, points_worth, members: [id, id]}``.
    """
    today = date.today()
    resp = api.get(
        "/api/v1/classes/instances",
        params={
            "gym_id": GYM_ID,
            "start_date": today.isoformat(),
            "end_date": (
                today + timedelta(days=_BOARD_WINDOW_DAYS)
            ).isoformat(),
        },
    )
    if resp.status_code != 200:
        return None
    for occ in resp.json()["items"]:
        if occ["is_cancelled"]:
            continue
        members = by_class.get(occ["class_id"])
        if members is None or len(members) < 2:
            continue
        return {
            "class_id": occ["class_id"],
            "occurrence_date": occ["class_date"],
            "points_worth": members[0]["points_worth"],
            "members": [members[0]["member_id"], members[1]["member_id"]],
        }
    return None


@pytest.fixture(scope="session")
def batch_ids(api: httpx.Client) -> dict:
    """Discover a multi-cover class + occurrence + a no-membership member."""

    async def _discover() -> dict:
        conn = await asyncpg.connect(_get_db_url())
        try:
            gym = UUID(GYM_ID)
            rows = await conn.fetch(_COVERING_MEMBERS_SQL, gym)
            by_class: dict[str, list[dict]] = {}
            for r in rows:
                by_class.setdefault(str(r["class_id"]), []).append(
                    {
                        "member_id": str(r["member_id"]),
                        "points_worth": int(r["points_worth"]),
                    }
                )
            return {
                "by_class": by_class,
                "no_membership": await conn.fetchrow(
                    _NO_MEMBERSHIP_MEMBER_SQL, gym
                ),
            }
        finally:
            await conn.close()

    try:
        ids = _run_async(_discover())
    except Exception as exc:  # noqa: BLE001 — any DB issue means skip, not fail
        pytest.skip(f"Seeded DB not reachable for discovery: {exc}")
    ids["target"] = _multi_covered_target(api, ids["by_class"])
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


def _teardown_batch(
    member_ids: list[str],
    class_history_id: str | None,
    new_activity_ids: set[UUID],
    points_by_member: dict[str, int],
) -> None:
    """Undo a test batch: delete each member's attendance for the occurrence,
    the new class_attended activities, the lazily-created class_history row, and
    restore every member's points_balance."""

    async def _run() -> None:
        conn = await asyncpg.connect(_get_db_url())
        try:
            if class_history_id is not None:
                await conn.execute(
                    "DELETE FROM member_attendance "
                    "WHERE class_history_id = $1 AND member_id = ANY($2)",
                    UUID(class_history_id),
                    [UUID(m) for m in member_ids],
                )
            if new_activity_ids:
                await conn.execute(
                    "DELETE FROM member_activities WHERE activity_id = ANY($1)",
                    list(new_activity_ids),
                )
            if class_history_id is not None:
                await conn.execute(
                    "DELETE FROM class_history WHERE class_history_id = $1",
                    UUID(class_history_id),
                )
            for member_id, points in points_by_member.items():
                await conn.execute(
                    "UPDATE members SET points_balance = $2 "
                    "WHERE member_id = $1",
                    UUID(member_id),
                    points,
                )
        finally:
            await conn.close()

    _run_async(_run())


# ---------------------------------------------------------------------------
# 422 validation (no DB writes / no seed needed)
# ---------------------------------------------------------------------------


class TestBatchCheckinValidation:
    """422 validation for the batch body shape + PATH params."""

    def _url(self, occurrence_date: str = "2026-06-01") -> str:
        return (
            f"/api/v1/classes/{uuid4()}"
            f"/occurrences/{occurrence_date}/checkin-batch"
        )

    def test_missing_body_returns_422(self, api: httpx.Client) -> None:
        resp = api.post(self._url())
        assert resp.status_code == 422

    def test_empty_member_ids_returns_422(self, api: httpx.Client) -> None:
        resp = api.post(
            self._url(),
            json={"gym_id": GYM_ID, "member_ids": []},
        )
        assert resp.status_code == 422

    def test_missing_gym_id_returns_422(self, api: httpx.Client) -> None:
        resp = api.post(
            self._url(),
            json={"member_ids": [str(uuid4())]},
        )
        assert resp.status_code == 422

    def test_invalid_member_uuid_returns_422(self, api: httpx.Client) -> None:
        resp = api.post(
            self._url(),
            json={"gym_id": GYM_ID, "member_ids": ["not-a-uuid"]},
        )
        assert resp.status_code == 422

    def test_invalid_occurrence_date_returns_422(
        self, api: httpx.Client
    ) -> None:
        resp = api.post(
            self._url(occurrence_date="not-a-date"),
            json={"gym_id": GYM_ID, "member_ids": [str(uuid4())]},
        )
        assert resp.status_code == 422


# ---------------------------------------------------------------------------
# Batch behavior (needs the seeded DB + the uq_class_history_occurrence
# migration for the materializer's ON CONFLICT — migration-blocked today).
# ---------------------------------------------------------------------------


class TestBatchCheckin:
    def test_mixed_batch_207_and_single_history_row(
        self, api: httpx.Client, batch_ids: dict
    ) -> None:
        """A mixed batch returns 207 with one checked_in, one
        already_checked_in, and one skipped(no_membership), materializing
        EXACTLY ONE class_history row for the occurrence regardless of member
        count. Fully cleaned up after."""
        target = batch_ids["target"]
        no_membership = batch_ids["no_membership"]
        if target is None or no_membership is None:
            pytest.skip(
                "No 2-cover class + membership-less member in seed/board"
            )
        member_a, member_b = target["members"]
        no_mem = str(no_membership["member_id"])
        class_id = target["class_id"]
        occurrence_date = target["occurrence_date"]
        points_worth = target["points_worth"]
        url = (
            f"/api/v1/classes/{class_id}"
            f"/occurrences/{occurrence_date}/checkin-batch"
        )

        before_points = {
            m: _member_points(m) for m in (member_a, member_b)
        }
        before_acts = {
            m: _class_attended_activity_ids(m, class_id)
            for m in (member_a, member_b)
        }

        # Pre-check member_a in so it is already_checked_in in the mixed batch.
        first = api.post(
            url, json={"gym_id": GYM_ID, "member_ids": [member_a]}
        )
        class_history_id = (
            first.json().get("class_history_id")
            if first.headers.get("content-type", "").startswith(
                "application/json"
            )
            else None
        )

        try:
            assert first.status_code == 207, first.text

            resp = api.post(
                url,
                json={
                    "gym_id": GYM_ID,
                    "member_ids": [member_a, member_b, no_mem],
                },
            )
            assert resp.status_code == 207, resp.text
            body = resp.json()
            class_history_id = body["class_history_id"]
            by_member = {r["member_id"]: r for r in body["results"]}

            assert by_member[member_a]["status"] == "already_checked_in"
            assert by_member[member_a]["points_awarded"] == 0
            assert by_member[member_b]["status"] == "checked_in"
            assert by_member[member_b]["points_awarded"] == points_worth
            assert by_member[no_mem]["status"] == "skipped"
            assert by_member[no_mem]["reason"] == "no_membership"

            # member_b's balance rose by exactly the class's points_worth.
            assert (
                _member_points(member_b)
                == before_points[member_b] + points_worth
            )
            # Exactly one class_history row for this (class, occurrence).
            assert _history_row_count(class_id, class_history_id) == 1
        finally:
            new_acts: set[UUID] = set()
            for m in (member_a, member_b):
                new_acts |= (
                    _class_attended_activity_ids(m, class_id) - before_acts[m]
                )
            _teardown_batch(
                [member_a, member_b], class_history_id, new_acts, before_points
            )

    def test_batch_re_post_is_idempotent(
        self, api: httpx.Client, batch_ids: dict
    ) -> None:
        """Re-posting the same batch is idempotent: every covered member is
        already_checked_in with 0 points and balances do not move."""
        target = batch_ids["target"]
        if target is None:
            pytest.skip("No 2-cover class + board occurrence in seed")
        member_a, member_b = target["members"]
        class_id = target["class_id"]
        occurrence_date = target["occurrence_date"]
        url = (
            f"/api/v1/classes/{class_id}"
            f"/occurrences/{occurrence_date}/checkin-batch"
        )
        payload = {"gym_id": GYM_ID, "member_ids": [member_a, member_b]}

        before_points = {
            m: _member_points(m) for m in (member_a, member_b)
        }
        before_acts = {
            m: _class_attended_activity_ids(m, class_id)
            for m in (member_a, member_b)
        }

        first = api.post(url, json=payload)
        class_history_id = (
            first.json().get("class_history_id")
            if first.headers.get("content-type", "").startswith(
                "application/json"
            )
            else None
        )
        try:
            assert first.status_code == 207, first.text
            after_first = {m: _member_points(m) for m in (member_a, member_b)}

            second = api.post(url, json=payload)
            assert second.status_code == 207, second.text
            for result in second.json()["results"]:
                assert result["status"] == "already_checked_in"
                assert result["points_awarded"] == 0
            # No extra points on the repeat.
            assert {
                m: _member_points(m) for m in (member_a, member_b)
            } == after_first
        finally:
            new_acts: set[UUID] = set()
            for m in (member_a, member_b):
                new_acts |= (
                    _class_attended_activity_ids(m, class_id) - before_acts[m]
                )
            _teardown_batch(
                [member_a, member_b], class_history_id, new_acts, before_points
            )


def _history_row_count(class_id: str, class_history_id: str | None) -> int:
    """Count class_history rows for the class that match the returned id's
    occurrence — proves the batch materialized exactly one occurrence row."""
    if class_history_id is None:
        return 0

    async def _run() -> int:
        conn = await asyncpg.connect(_get_db_url())
        try:
            return await conn.fetchval(
                "SELECT COUNT(*) FROM class_history "
                "WHERE class_id = $1 AND occurred_at = ("
                "  SELECT occurred_at FROM class_history "
                "  WHERE class_history_id = $2)",
                UUID(class_id),
                UUID(class_history_id),
            )
        finally:
            await conn.close()

    return _run_async(_run())
