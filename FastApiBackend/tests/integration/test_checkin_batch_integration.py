"""Live integration tests for the batch staff check-in.

Endpoint under test:
  POST /api/v1/checkin/batch   (class_id + occurrence_date in the body)

Same live-discovery approach as test_checkin_integration.py: rather than
hard-code seed ids (which drift every reseed), the suite DISCOVERS a class with
>= 2 covering members (active UNLIMITED eligible plan), a board occurrence for
it, and a membership-less member, then exercises a mixed batch + an idempotent
re-post. It cleans up EXACTLY what it creates (attendance rows, keyed by their
identity — class_id + original_date — + new class_attended activities) and
restores each member's points_balance.

``occurrence_date`` (both requested and read off the board) is always the
occurrence's ORIGINAL date (``EffectiveClassInstanceResponse.original_date``),
never the effective/display ``class_date``.

NOTE: occurrences are versioned-schedule computations (no materialized
occurrence table); a read against a column or constraint that doesn't exist
yet is a migration-not-applied gap, not a code defect.

The ``all_failed -> 500`` status mapping is covered deterministically (no DB) in
``tests/checkin/test_checkin_router.py::test_batch_checkin_total_failure_returns_500``.
It is intentionally NOT asserted here.
"""

from __future__ import annotations

import asyncio
from collections.abc import Iterator
from datetime import UTC, date, datetime, time, timedelta
from uuid import UUID, uuid4

import asyncpg
import httpx
import pytest
from dotenv import dotenv_values

from tests.helpers.waiver_compliance import WaiverCompliance
from tests.seed_constants import SEEDED_GYM_ID

GYM_ID = SEEDED_GYM_ID

_ENV_PATH = "/var/home/jm/Documents/CombatDen/codebase/FastApiBackend/.env"
# How far ahead to scan the schedule board for a usable occurrence.
_BOARD_WINDOW_DAYS = 45
# Mirror settings.checkin_opens_hours_before_start: only an occurrence starting
# within this window (or already past) can be checked into.
_CHECKIN_OPENS_HOURS = 2

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
    ``{class_id, occurrence_date, occurrence_time, points_worth, members: [id, id]}``.
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
    cutoff = datetime.now(UTC) + timedelta(hours=_CHECKIN_OPENS_HOURS)
    for occ in resp.json()["items"]:
        if occ["is_cancelled"]:
            continue
        # Skip occurrences too far out to check into yet (the 2h early window).
        if datetime.fromisoformat(occ["occurred_at"]) > cutoff:
            continue
        members = by_class.get(occ["class_id"])
        if members is None or len(members) < 2:
            continue
        return {
            "class_id": occ["class_id"],
            # Always the ORIGINAL slot -- never class_date. A class may occur
            # several times per day, so the time is part of the identity.
            "occurrence_date": occ["original_date"],
            "occurrence_time": occ["original_time"],
            "points_worth": members[0]["points_worth"],
            "members": [members[0]["member_id"], members[1]["member_id"]],
        }
    return None


@pytest.fixture(scope="session")
def batch_ids(api: httpx.Client) -> Iterator[dict]:
    """Discover a multi-cover class + occurrence + a no-membership member.

    Both picked covering members are then made WAIVER-COMPLIANT (see
    ``tests/helpers/waiver_compliance.py``): the seed deliberately leaves every
    member unsigned, and the check-in gate warns + records nothing for an
    unsigned member, so the recording tests must establish that precondition
    themselves. The signatures created here are deleted at session end.
    """

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

    compliance = WaiverCompliance(api, GYM_ID)
    if ids["target"] is not None:
        for member_id in ids["target"]["members"]:
            compliance.ensure_signed(member_id)
    try:
        yield ids
    finally:
        compliance.cleanup()


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
    class_id: str,
    occurrence_date: str,
    occurrence_time: str,
    new_activity_ids: set[UUID],
    points_by_member: dict[str, int],
) -> None:
    """Undo a test batch: delete each member's attendance for the occurrence
    (keyed by its full identity — class_id + original_date + original_time),
    the new class_attended activities, and restore every member's
    points_balance."""

    async def _run() -> None:
        conn = await asyncpg.connect(_get_db_url())
        try:
            await conn.execute(
                "DELETE FROM member_attendance "
                "WHERE class_id = $1 AND original_date = $2 "
                "AND original_time = $3 AND member_id = ANY($4)",
                UUID(class_id),
                date.fromisoformat(occurrence_date),
                time.fromisoformat(occurrence_time),
                [UUID(m) for m in member_ids],
            )
            if new_activity_ids:
                await conn.execute(
                    "DELETE FROM member_activities WHERE activity_id = ANY($1)",
                    list(new_activity_ids),
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


_BATCH_URL = "/api/v1/checkin/batch"


class TestBatchCheckinValidation:
    """422 validation for the batch body shape (class_id + occurrence_date +
    occurrence_time now ride in the body, not the path)."""

    def test_missing_body_returns_422(self, api: httpx.Client) -> None:
        resp = api.post(_BATCH_URL)
        assert resp.status_code == 422

    def test_empty_member_ids_returns_422(self, api: httpx.Client) -> None:
        resp = api.post(
            _BATCH_URL,
            json={
                "gym_id": GYM_ID,
                "class_id": str(uuid4()),
                "occurrence_date": "2026-06-01",
                "occurrence_time": "17:00:00",
                "member_ids": [],
            },
        )
        assert resp.status_code == 422

    def test_missing_gym_id_returns_422(self, api: httpx.Client) -> None:
        resp = api.post(
            _BATCH_URL,
            json={
                "class_id": str(uuid4()),
                "occurrence_date": "2026-06-01",
                "occurrence_time": "17:00:00",
                "member_ids": [str(uuid4())],
            },
        )
        assert resp.status_code == 422

    def test_missing_class_id_returns_422(self, api: httpx.Client) -> None:
        resp = api.post(
            _BATCH_URL,
            json={
                "gym_id": GYM_ID,
                "occurrence_date": "2026-06-01",
                "occurrence_time": "17:00:00",
                "member_ids": [str(uuid4())],
            },
        )
        assert resp.status_code == 422

    def test_invalid_member_uuid_returns_422(self, api: httpx.Client) -> None:
        resp = api.post(
            _BATCH_URL,
            json={
                "gym_id": GYM_ID,
                "class_id": str(uuid4()),
                "occurrence_date": "2026-06-01",
                "occurrence_time": "17:00:00",
                "member_ids": ["not-a-uuid"],
            },
        )
        assert resp.status_code == 422

    def test_invalid_occurrence_date_returns_422(
        self, api: httpx.Client
    ) -> None:
        resp = api.post(
            _BATCH_URL,
            json={
                "gym_id": GYM_ID,
                "class_id": str(uuid4()),
                "occurrence_date": "not-a-date",
                "occurrence_time": "17:00:00",
                "member_ids": [str(uuid4())],
            },
        )
        assert resp.status_code == 422


# ---------------------------------------------------------------------------
# Batch behavior (needs the seeded DB + the versioned schedule migration).
# ---------------------------------------------------------------------------


class TestBatchCheckin:
    def test_mixed_batch_207(
        self, api: httpx.Client, batch_ids: dict
    ) -> None:
        """A mixed KIOSK batch (is_member=True) returns 207 with one checked_in,
        one already_checked_in, and one skipped(no_membership). Fully cleaned
        up after."""
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
        occurrence_time = target["occurrence_time"]
        points_worth = target["points_worth"]

        before_points = {
            m: _member_points(m) for m in (member_a, member_b)
        }
        before_acts = {
            m: _class_attended_activity_ids(m, class_id)
            for m in (member_a, member_b)
        }

        # Pre-check member_a in so it is already_checked_in in the mixed batch.
        first = api.post(
            _BATCH_URL,
            json={
                "gym_id": GYM_ID,
                "class_id": class_id,
                "occurrence_date": occurrence_date,
                "occurrence_time": occurrence_time,
                "member_ids": [member_a],
            },
        )

        try:
            assert first.status_code == 207, first.text

            resp = api.post(
                _BATCH_URL,
                json={
                    "gym_id": GYM_ID,
                    "class_id": class_id,
                    "occurrence_date": occurrence_date,
                    "occurrence_time": occurrence_time,
                    "member_ids": [member_a, member_b, no_mem],
                    "is_member": True,
                },
            )
            assert resp.status_code == 207, resp.text
            body = resp.json()
            by_member = {r["member_id"]: r for r in body["results"]}

            assert by_member[member_a]["status"] == "already_checked_in"
            # A repeat echoes the class's points (already awarded, not re-added).
            assert by_member[member_a]["points_awarded"] == points_worth
            assert by_member[member_b]["status"] == "checked_in"
            assert by_member[member_b]["points_awarded"] == points_worth
            # Kiosk gate rejects the membership-less member.
            assert by_member[no_mem]["status"] == "skipped"
            assert by_member[no_mem]["reason"] == "no_membership"

            # member_b's balance rose by exactly the class's points_worth.
            assert (
                _member_points(member_b)
                == before_points[member_b] + points_worth
            )
        finally:
            new_acts: set[UUID] = set()
            for m in (member_a, member_b):
                new_acts |= (
                    _class_attended_activity_ids(m, class_id) - before_acts[m]
                )
            _teardown_batch(
                [member_a, member_b],
                class_id,
                occurrence_date,
                occurrence_time,
                new_acts,
                before_points,
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
        occurrence_time = target["occurrence_time"]
        payload = {
            "gym_id": GYM_ID,
            "class_id": class_id,
            "occurrence_date": occurrence_date,
            "occurrence_time": occurrence_time,
            "member_ids": [member_a, member_b],
        }

        before_points = {
            m: _member_points(m) for m in (member_a, member_b)
        }
        before_acts = {
            m: _class_attended_activity_ids(m, class_id)
            for m in (member_a, member_b)
        }

        first = api.post(_BATCH_URL, json=payload)
        try:
            assert first.status_code == 207, first.text
            after_first = {m: _member_points(m) for m in (member_a, member_b)}

            second = api.post(_BATCH_URL, json=payload)
            assert second.status_code == 207, second.text
            for result in second.json()["results"]:
                assert result["status"] == "already_checked_in"
                # Repeat echoes the class's points (already awarded, not re-added).
                assert result["points_awarded"] == target["points_worth"]
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
                [member_a, member_b],
                class_id,
                occurrence_date,
                occurrence_time,
                new_acts,
                before_points,
            )

    def test_staff_batch_holds_no_membership_then_override_records(
        self, api: httpx.Client, batch_ids: dict
    ) -> None:
        """A STAFF batch (is_member=False) records the covered member but holds a
        membership-less one as needs_confirmation (not recorded); resending with
        ignore_warnings records it (checked_in, NULL attribution, no_membership
        warning). Fully cleaned up after."""
        target = batch_ids["target"]
        no_membership = batch_ids["no_membership"]
        if target is None or no_membership is None:
            pytest.skip(
                "No 2-cover class + membership-less member in seed/board"
            )
        member_a = target["members"][0]
        no_mem = str(no_membership["member_id"])
        class_id = target["class_id"]
        occurrence_date = target["occurrence_date"]
        occurrence_time = target["occurrence_time"]

        before_points = {m: _member_points(m) for m in (member_a, no_mem)}
        before_acts = {
            m: _class_attended_activity_ids(m, class_id)
            for m in (member_a, no_mem)
        }

        resp = api.post(
            _BATCH_URL,
            json={
                "gym_id": GYM_ID,
                "class_id": class_id,
                "occurrence_date": occurrence_date,
                "occurrence_time": occurrence_time,
                "member_ids": [member_a, no_mem],
                # is_member omitted -> staff (False) by default.
            },
        )
        try:
            assert resp.status_code == 207, resp.text
            by_member = {r["member_id"]: r for r in resp.json()["results"]}

            # The covered member records cleanly (no warnings).
            assert by_member[member_a]["status"] == "checked_in"
            assert by_member[member_a]["warnings"] == []

            # The membership-less member is held for confirmation, not recorded.
            no_mem_row = by_member[no_mem]
            assert no_mem_row["status"] == "needs_confirmation"
            assert no_mem_row["log_id"] is None
            assert "no_membership" in no_mem_row["warnings"]

            # Resending with ignore_warnings records the warned member.
            override = api.post(
                _BATCH_URL,
                json={
                    "gym_id": GYM_ID,
                    "class_id": class_id,
                    "occurrence_date": occurrence_date,
                    "occurrence_time": occurrence_time,
                    "member_ids": [no_mem],
                    "ignore_warnings": True,
                },
            )
            assert override.status_code == 207, override.text
            o_row = override.json()["results"][0]
            assert o_row["status"] == "checked_in"
            assert o_row["chosen_plan_id"] is None
            assert o_row["chosen_item_id"] is None
            assert "no_membership" in o_row["warnings"]
            assert o_row["log_id"] is not None
        finally:
            new_acts: set[UUID] = set()
            for m in (member_a, no_mem):
                new_acts |= (
                    _class_attended_activity_ids(m, class_id) - before_acts[m]
                )
            _teardown_batch(
                [member_a, no_mem],
                class_id,
                occurrence_date,
                occurrence_time,
                new_acts,
                before_points,
            )
