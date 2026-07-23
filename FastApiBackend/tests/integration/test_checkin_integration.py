"""Live integration tests for the checkin domain (gated check-in + streak).

Endpoints under test:
  POST /api/v1/checkin   (class_id + occurrence_date; the occurrence is
                          resolved -- a pure read, no materialization --
                          then gated: plan + room capacity + points + override)
  GET  /api/v1/streak

These run against the live backend + the seeded DB. Rather than hard-code seed
ids (which drift every reseed), the suite DISCOVERS suitable rows from the DB at
session start and skips gracefully when the DB isn't reachable / seeded. The
``api`` fixture (this directory's own conftest.py) provides an authorised
client; ``SEEDED_GYM_ID`` is the single seeded gym. The schedule board it reads
(``GET /api/v1/classes/instances``) stays in the classes domain.

``occurrence_date`` (both requested and read off the board) is always the
occurrence's ORIGINAL date (``EffectiveClassInstanceResponse.original_date``),
never the effective/display ``class_date`` — see the class-system-guide skill.

NOTE: occurrences are versioned-schedule computations now (there is no
materialized occurrence table); a check-in / attendance read against a
column or constraint that doesn't exist yet is a migration-not-applied gap,
not a code defect.
"""

from __future__ import annotations

import asyncio
from collections.abc import Iterator
from datetime import UTC, date, datetime, time, timedelta
from uuid import UUID, uuid4
from zoneinfo import ZoneInfo

import asyncpg
import httpx
import pytest
from dotenv import dotenv_values
from sqlalchemy import text

from src.checkin import SQL_DIR
from src.checkin.service.streak_service import StreakService
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql
from tests.helpers import board_targets
from tests.helpers.waiver_compliance import WaiverCompliance
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


# An existing attendance row -> a member with attendance, for the streak test.
_EXISTING_ATTENDANCE_SQL = """
SELECT member_id, class_id, original_date, log_id, plan_id, item_id
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

# A member with ZERO attendance rows at all -> a clean slate for the streak
# week-boundary regression test (isolates the synthetic row from any real
# seed/test attendance history).
_ATTENDANCE_FREE_MEMBER_SQL = """
SELECT m.member_id
FROM members m
WHERE m.gym_id = $1
  AND NOT EXISTS (
      SELECT 1 FROM member_attendance ma WHERE ma.member_id = m.member_id
  )
LIMIT 1
"""

# Any class at the gym -> just needs to satisfy member_attendance's FKs.
_ANY_CLASS_ID_SQL = """
SELECT class_id FROM gym_classes WHERE gym_id = $1 LIMIT 1
"""

def _pick_target(
    board: list[dict],
    covering: dict[str, list[dict]],
    attended: set[tuple[str, str, str, str]],
    gym_timezone: str,
    *,
    checkin_open: bool,
) -> dict | None:
    """One freshly-checkin-able (member, occurrence) target, or None.

    ``checkin_open=True`` -> a target that can be checked into now (already
    past, in session, or starting inside the open window); ``False`` -> one too
    far in the future to check into yet. See ``tests/helpers/board_targets.py``
    for why the pick has to scan backward and re-check coverage.
    """
    picked = board_targets.pick_occurrence(
        board,
        covering,
        attended,
        gym_timezone,
        checkin_open=checkin_open,
    )
    if picked is None:
        return None
    occurrence, members = picked
    return {
        "member_id": members[0]["member_id"],
        "class_id": occurrence["class_id"],
        "points_worth": members[0]["points_worth"],
        # occurrence_date/time are always the ORIGINAL slot -- never
        # class_date (the effective/display date), per the
        # class-system-guide skill. A class may occur several times per
        # day, so the time is part of the occurrence's identity.
        "occurrence_date": occurrence["original_date"],
        "occurrence_time": occurrence["original_time"],
    }


@pytest.fixture(scope="session")
def seed_ids(api: httpx.Client) -> Iterator[dict]:
    """Discover usable ids from the live seeded DB + board; skip if unavailable.

    The picked ``covered`` member is then made WAIVER-COMPLIANT (see
    ``tests/helpers/waiver_compliance.py``): the seed deliberately leaves every
    member unsigned, and the check-in gate warns + records nothing for an
    unsigned member, so the recording tests must establish that precondition
    themselves. The signatures created here are deleted at session end.
    """

    async def _discover() -> dict:
        conn = await asyncpg.connect(_get_db_url())
        try:
            gym = UUID(GYM_ID)
            return {
                "covering": await board_targets.load_covering(conn, GYM_ID),
                "attended": await board_targets.load_attended_keys(conn, GYM_ID),
                "existing": await conn.fetchrow(_EXISTING_ATTENDANCE_SQL, gym),
                "no_membership": await conn.fetchrow(_NO_MEMBERSHIP_MEMBER_SQL, gym),
                "attendance_free_member": await conn.fetchrow(
                    _ATTENDANCE_FREE_MEMBER_SQL, gym
                ),
                "any_class_id": await conn.fetchval(_ANY_CLASS_ID_SQL, gym),
                "gym_timezone": await board_targets.load_gym_timezone(
                    conn, GYM_ID
                ),
            }
        finally:
            await conn.close()

    try:
        ids = _run_async(_discover())
    except (OSError, asyncpg.PostgresConnectionError) as exc:
        # ONLY an unreachable/dropped DB skips — a query bug (bad column,
        # type error) is a real regression that must fail loudly, not vanish
        # into a green skip for the whole session-scoped fixture.
        pytest.skip(f"Seeded DB not reachable for discovery: {exc}")
    board = board_targets.fetch_board(api, GYM_ID)
    ids["covered"] = _pick_target(
        board,
        ids["covering"],
        ids["attended"],
        ids["gym_timezone"],
        checkin_open=True,
    )
    ids["too_early"] = _pick_target(
        board,
        ids["covering"],
        ids["attended"],
        ids["gym_timezone"],
        checkin_open=False,
    )

    compliance = WaiverCompliance(api, GYM_ID)
    if ids["covered"] is not None:
        compliance.ensure_signed(ids["covered"]["member_id"])
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


def _attendance_exists(
    member_id: str, class_id: str, occurrence_date: str, occurrence_time: str
) -> bool:
    async def _run() -> bool:
        conn = await asyncpg.connect(_get_db_url())
        try:
            return await conn.fetchval(
                "SELECT EXISTS (SELECT 1 FROM member_attendance "
                "WHERE member_id = $1 AND class_id = $2 AND original_date = $3 "
                "AND original_time = $4)",
                UUID(member_id),
                UUID(class_id),
                date.fromisoformat(occurrence_date),
                time.fromisoformat(occurrence_time),
            )
        finally:
            await conn.close()

    return _run_async(_run())


def _insert_raw_attendance(
    member_id: str,
    class_id: str,
    original_date: date,
    original_time: time,
    occurred_at: datetime,
) -> None:
    """Insert a bare member_attendance row directly (no covering membership --
    plan_id/item_id stay NULL together), for the streak week-boundary
    regression test below."""

    async def _run() -> None:
        conn = await asyncpg.connect(_get_db_url())
        try:
            await conn.execute(
                "INSERT INTO member_attendance "
                "(member_id, gym_id, class_id, original_date, original_time, "
                "occurred_at) VALUES ($1, $2, $3, $4, $5, $6)",
                UUID(member_id),
                UUID(GYM_ID),
                UUID(class_id),
                original_date,
                original_time,
                occurred_at,
            )
        finally:
            await conn.close()

    _run_async(_run())


def _delete_raw_attendance(
    member_id: str, class_id: str, original_date: date
) -> None:
    async def _run() -> None:
        conn = await asyncpg.connect(_get_db_url())
        try:
            await conn.execute(
                "DELETE FROM member_attendance "
                "WHERE member_id = $1 AND class_id = $2 AND original_date = $3",
                UUID(member_id),
                UUID(class_id),
                original_date,
            )
        finally:
            await conn.close()

    _run_async(_run())


def _teardown_checkin(
    member_id: str,
    class_id: str,
    occurrence_date: str,
    occurrence_time: str,
    new_activity_ids: set[UUID],
    restore_points: int,
) -> None:
    """Undo a test check-in: delete the attendance row (keyed by its full
    identity — class_id + original_date + original_time) + the new
    class_attended activities, restore points."""

    async def _run() -> None:
        conn = await asyncpg.connect(_get_db_url())
        try:
            await conn.execute(
                "DELETE FROM member_attendance "
                "WHERE member_id = $1 AND class_id = $2 AND original_date = $3 "
                "AND original_time = $4",
                UUID(member_id),
                UUID(class_id),
                date.fromisoformat(occurrence_date),
                time.fromisoformat(occurrence_time),
            )
            if new_activity_ids:
                await conn.execute(
                    "DELETE FROM member_activities WHERE activity_id = ANY($1)",
                    list(new_activity_ids),
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
# POST /api/v1/checkin — 422 validation (no DB writes / no seed needed)
# ---------------------------------------------------------------------------


class TestCheckinValidation:
    """422 validation for the (class_id + occurrence_date + occurrence_time)
    body shape."""

    def test_missing_body_returns_422(self, api: httpx.Client) -> None:
        resp = api.post("/api/v1/checkin")
        assert resp.status_code == 422

    def test_missing_member_id_returns_422(self, api: httpx.Client) -> None:
        resp = api.post(
            "/api/v1/checkin",
            json={
                "gym_id": GYM_ID,
                "class_id": str(uuid4()),
                "occurrence_date": "2026-06-01",
                "occurrence_time": "17:00:00",
            },
        )
        assert resp.status_code == 422

    def test_missing_class_id_returns_422(self, api: httpx.Client) -> None:
        resp = api.post(
            "/api/v1/checkin",
            json={
                "member_id": str(uuid4()),
                "gym_id": GYM_ID,
                "occurrence_date": "2026-06-01",
                "occurrence_time": "17:00:00",
            },
        )
        assert resp.status_code == 422

    def test_missing_occurrence_date_returns_422(self, api: httpx.Client) -> None:
        resp = api.post(
            "/api/v1/checkin",
            json={
                "member_id": str(uuid4()),
                "gym_id": GYM_ID,
                "class_id": str(uuid4()),
                "occurrence_time": "17:00:00",
            },
        )
        assert resp.status_code == 422

    def test_missing_occurrence_time_returns_422(self, api: httpx.Client) -> None:
        resp = api.post(
            "/api/v1/checkin",
            json={
                "member_id": str(uuid4()),
                "gym_id": GYM_ID,
                "class_id": str(uuid4()),
                "occurrence_date": "2026-06-01",
            },
        )
        assert resp.status_code == 422

    def test_invalid_uuid_returns_422(self, api: httpx.Client) -> None:
        resp = api.post(
            "/api/v1/checkin",
            json={
                "member_id": "not-a-uuid",
                "gym_id": GYM_ID,
                "class_id": str(uuid4()),
                "occurrence_date": "2026-06-01",
                "occurrence_time": "17:00:00",
            },
        )
        assert resp.status_code == 422

    def test_invalid_date_returns_422(self, api: httpx.Client) -> None:
        resp = api.post(
            "/api/v1/checkin",
            json={
                "member_id": str(uuid4()),
                "gym_id": GYM_ID,
                "class_id": str(uuid4()),
                "occurrence_date": "not-a-date",
                "occurrence_time": "17:00:00",
            },
        )
        assert resp.status_code == 422


# ---------------------------------------------------------------------------
# POST /api/v1/checkin — gated behavior (needs the seeded DB + the versioned
# schedule migration applied)
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
        occurrence_time = row["occurrence_time"]

        before_points = _member_points(member_id)
        before_activities = _class_attended_activity_ids(member_id, class_id)

        resp = api.post(
            "/api/v1/checkin",
            json={
                "member_id": member_id,
                "gym_id": GYM_ID,
                "class_id": class_id,
                "occurrence_date": occurrence_date,
                "occurrence_time": occurrence_time,
            },
        )
        body = resp.json()
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
            _teardown_checkin(
                member_id,
                class_id,
                occurrence_date,
                occurrence_time,
                new_activity_ids,
                before_points,
            )

    def test_checkin_rejected_too_far_in_the_future(
        self, api: httpx.Client, seed_ids: dict
    ) -> None:
        """A check-in for an occurrence further than the open window before it
        starts is rejected (check-in isn't open yet) — nothing recorded."""
        row = seed_ids["too_early"]
        if row is None:
            pytest.skip("No too-far-future coverable occurrence on the board")
        resp = api.post(
            "/api/v1/checkin",
            json={
                "member_id": row["member_id"],
                "gym_id": GYM_ID,
                "class_id": row["class_id"],
                "occurrence_date": row["occurrence_date"],
                "occurrence_time": row["occurrence_time"],
            },
        )
        assert resp.status_code == 400, resp.text
        assert "not open" in resp.json()["detail"].lower()

    def test_remove_checkin_reverses_attendance_points_and_activity(
        self, api: httpx.Client, seed_ids: dict
    ) -> None:
        """DELETE /checkin removes one member's attendance, claws back the
        awarded points (balance back to before), and drops the class_attended
        activity. A second remove is a clean no-op (removed=False)."""
        row = seed_ids["covered"]
        if row is None:
            pytest.skip("No board occurrence for a coverable class in seed")
        member_id = row["member_id"]
        class_id = row["class_id"]
        points_worth = row["points_worth"]
        occurrence_date = row["occurrence_date"]
        occurrence_time = row["occurrence_time"]
        params = {
            "member_id": member_id,
            "gym_id": GYM_ID,
            "class_id": class_id,
            "occurrence_date": occurrence_date,
            "occurrence_time": occurrence_time,
        }

        before_points = _member_points(member_id)
        before_activities = _class_attended_activity_ids(member_id, class_id)

        checkin = api.post("/api/v1/checkin", json=params)
        assert checkin.status_code == 200, checkin.text
        if checkin.json()["already_checked_in"]:
            pytest.skip("covered member already seeded onto this occurrence")
        try:
            assert _member_points(member_id) == before_points + points_worth

            removed = api.request("DELETE", "/api/v1/checkin", params=params)
            assert removed.status_code == 200, removed.text
            body = removed.json()
            assert body["removed"] is True
            assert body["points_reverted"] == points_worth
            # Attendance + points + activity reverted to the pre-check-in state.
            assert (
                _attendance_exists(member_id, class_id, occurrence_date, occurrence_time)
                is False
            )
            assert _member_points(member_id) == before_points
            assert (
                _class_attended_activity_ids(member_id, class_id)
                == before_activities
            )

            # A second remove is a clean no-op.
            again = api.request("DELETE", "/api/v1/checkin", params=params)
            assert again.status_code == 200, again.text
            assert again.json()["removed"] is False
        finally:
            _teardown_checkin(
                member_id, class_id, occurrence_date, occurrence_time, set(), before_points
            )

    def test_duplicate_checkin_is_idempotent_and_awards_no_extra_points(
        self, api: httpx.Client, seed_ids: dict
    ) -> None:
        """A second check-in for the same (member, occurrence) is idempotent:
        already_checked_in=True, the points echoed (not re-awarded), balance
        unchanged."""
        row = seed_ids["covered"]
        if row is None:
            pytest.skip("No board occurrence for a coverable class in seed")
        member_id = row["member_id"]
        class_id = row["class_id"]
        occurrence_date = row["occurrence_date"]
        occurrence_time = row["occurrence_time"]
        payload = {
            "member_id": member_id,
            "gym_id": GYM_ID,
            "class_id": class_id,
            "occurrence_date": occurrence_date,
            "occurrence_time": occurrence_time,
        }

        before_points = _member_points(member_id)
        before_activities = _class_attended_activity_ids(member_id, class_id)

        first = api.post("/api/v1/checkin", json=payload)
        try:
            assert first.status_code == 200, first.text
            after_first_points = _member_points(member_id)
            awarded = first.json()["points_awarded"]

            second = api.post("/api/v1/checkin", json=payload)
            assert second.status_code == 200, second.text
            body = second.json()
            assert body["already_checked_in"] is True
            # The repeat echoes the class's points (already awarded), not 0.
            assert body["points_awarded"] == awarded
            # No EXTRA points on the repeat — the balance doesn't move.
            assert _member_points(member_id) == after_first_points
        finally:
            after_activities = _class_attended_activity_ids(member_id, class_id)
            _teardown_checkin(
                member_id,
                class_id,
                occurrence_date,
                occurrence_time,
                after_activities - before_activities,
                before_points,
            )

    def test_kiosk_checkin_without_membership_is_rejected(
        self, api: httpx.Client, seed_ids: dict
    ) -> None:
        """A KIOSK check-in (is_member=True) of a member with no active
        membership is rejected: null log_id, skip_reason=no_membership, nothing
        written (no cleanup needed)."""
        covered = seed_ids["covered"]
        member_row = seed_ids["no_membership"]
        if covered is None or member_row is None:
            pytest.skip("No membership-less member / coverable class in seed")
        member_id = str(member_row["member_id"])
        class_id = covered["class_id"]
        occurrence_date = covered["occurrence_date"]
        occurrence_time = covered["occurrence_time"]

        resp = api.post(
            "/api/v1/checkin",
            json={
                "member_id": member_id,
                "gym_id": GYM_ID,
                "class_id": class_id,
                "occurrence_date": occurrence_date,
                "occurrence_time": occurrence_time,
                "is_member": True,
            },
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["log_id"] is None
        assert body["chosen_plan_id"] is None
        assert body["already_checked_in"] is False
        assert body["points_awarded"] == 0
        assert body["skip_reason"] == "no_membership"

    def test_staff_checkin_without_membership_records_null_and_warns(
        self, api: httpx.Client, seed_ids: dict
    ) -> None:
        """A STAFF check-in (is_member=False) of a member with no active
        membership is held for confirmation (requires_confirmation, nothing
        written); resending with ignore_warnings records it — NULL plan/item
        attribution, a no_membership warning, points awarded. Fully cleaned up."""
        covered = seed_ids["covered"]
        member_row = seed_ids["no_membership"]
        if covered is None or member_row is None:
            pytest.skip("No membership-less member / coverable class in seed")
        member_id = str(member_row["member_id"])
        class_id = covered["class_id"]
        points_worth = covered["points_worth"]
        occurrence_date = covered["occurrence_date"]
        occurrence_time = covered["occurrence_time"]

        before_points = _member_points(member_id)
        before_activities = _class_attended_activity_ids(member_id, class_id)
        payload = {
            "member_id": member_id,
            "gym_id": GYM_ID,
            "class_id": class_id,
            "occurrence_date": occurrence_date,
            "occurrence_time": occurrence_time,
        }

        # Default: held for confirmation — nothing written, no points.
        first = api.post("/api/v1/checkin", json=payload)
        assert first.status_code == 200, first.text
        first_body = first.json()
        assert first_body["log_id"] is None
        assert first_body["requires_confirmation"] is True
        assert "no_membership" in first_body["warnings"]
        assert _member_points(member_id) == before_points

        # Override: records with NULL attribution + points.
        resp = api.post(
            "/api/v1/checkin", json={**payload, "ignore_warnings": True}
        )
        body = resp.json()
        after_activities = _class_attended_activity_ids(member_id, class_id)
        new_activity_ids = after_activities - before_activities
        try:
            assert resp.status_code == 200, resp.text
            assert body["log_id"] is not None
            UUID(body["log_id"])
            assert body["already_checked_in"] is False
            assert body["chosen_plan_id"] is None
            assert body["chosen_item_id"] is None
            assert "no_membership" in body["warnings"]
            assert body["requires_confirmation"] is False
            assert body["skip_reason"] is None
            assert body["points_awarded"] == points_worth
            assert _member_points(member_id) == before_points + points_worth
            assert len(new_activity_ids) == 1
        finally:
            _teardown_checkin(
                member_id,
                class_id,
                occurrence_date,
                occurrence_time,
                new_activity_ids,
                before_points,
            )


# ---------------------------------------------------------------------------
# GET /api/v1/checkin/attendees
# ---------------------------------------------------------------------------


class TestAttendees:
    def test_attendees_lists_a_null_membership_checkin(
        self, api: httpx.Client, seed_ids: dict
    ) -> None:
        """After a staff check-in of a no-membership member, the attendees
        endpoint lists that member with NULL plan/item attribution. Fully
        cleaned up."""
        covered = seed_ids["covered"]
        member_row = seed_ids["no_membership"]
        if covered is None or member_row is None:
            pytest.skip("No membership-less member / coverable class in seed")
        member_id = str(member_row["member_id"])
        class_id = covered["class_id"]
        occurrence_date = covered["occurrence_date"]
        occurrence_time = covered["occurrence_time"]

        before_points = _member_points(member_id)
        before_activities = _class_attended_activity_ids(member_id, class_id)

        # A no-membership staff check-in needs the override to actually record
        # (warn-first holds it for confirmation otherwise) — we want the
        # NULL-attribution attendance row so the attendees list can surface it.
        checkin = api.post(
            "/api/v1/checkin",
            json={
                "member_id": member_id,
                "gym_id": GYM_ID,
                "class_id": class_id,
                "occurrence_date": occurrence_date,
                "occurrence_time": occurrence_time,
                "ignore_warnings": True,
            },
        )
        try:
            assert checkin.status_code == 200, checkin.text

            resp = api.get(
                "/api/v1/checkin/attendees",
                params={
                    "gym_id": GYM_ID,
                    "class_id": class_id,
                    "occurrence_date": occurrence_date,
                    "occurrence_time": occurrence_time,
                },
            )
            assert resp.status_code == 200, resp.text
            body = resp.json()
            by_member = {a["member_id"]: a for a in body["attendees"]}
            assert member_id in by_member
            attendee = by_member[member_id]
            assert attendee["plan_id"] is None
            assert attendee["item_id"] is None
            assert attendee["full_name"]
        finally:
            new_activity_ids = (
                _class_attended_activity_ids(member_id, class_id)
                - before_activities
            )
            _teardown_checkin(
                member_id,
                class_id,
                occurrence_date,
                occurrence_time,
                new_activity_ids,
                before_points,
            )

    def test_attendees_empty_when_no_signups_or_attendance(
        self, api: httpx.Client, seed_ids: dict
    ) -> None:
        """An occurrence with no sign-ups or check-ins returns an empty
        attendee list."""
        covered = seed_ids["covered"]
        if covered is None:
            pytest.skip("No coverable class in seed")

        resp = api.get(
            "/api/v1/checkin/attendees",
            params={
                "gym_id": GYM_ID,
                "class_id": covered["class_id"],
                # A date nobody has signed up for or attended.
                "occurrence_date": "2999-12-31",
                "occurrence_time": "00:00:00",
            },
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["attendees"] == []

    def test_attendees_unknown_gym_returns_403_or_404(
        self, api: httpx.Client
    ) -> None:
        """An unknown gym_id is rejected — employee auth
        (``verify_roles``) runs before the service, so an unknown gym
        403s (the service itself no longer checks gym existence directly:
        occurrence resolution is keyed by (class_id, original_date,
        original_time), with no separate gym-timezone read)."""
        resp = api.get(
            "/api/v1/checkin/attendees",
            params={
                "gym_id": str(uuid4()),
                "class_id": str(uuid4()),
                "occurrence_date": "2026-06-01",
                "occurrence_time": "00:00:00",
            },
        )
        # 403 (not an employee of the unknown gym) or 404 are both valid
        # rejections; the point is it is not a 200 with data.
        assert resp.status_code in (403, 404), resp.text


# ---------------------------------------------------------------------------
# GET /api/v1/streak
# ---------------------------------------------------------------------------


class TestStreakValidation:
    """422 validation for GET /api/v1/streak — no DB writes."""

    def test_missing_params_returns_422(self, api: httpx.Client) -> None:
        resp = api.get("/api/v1/streak")
        assert resp.status_code == 422

    def test_missing_gym_id_returns_422(self, api: httpx.Client) -> None:
        resp = api.get(
            "/api/v1/streak", params={"member_id": str(uuid4())}
        )
        assert resp.status_code == 422

    def test_missing_member_id_returns_422(self, api: httpx.Client) -> None:
        resp = api.get("/api/v1/streak", params={"gym_id": GYM_ID})
        assert resp.status_code == 422

    def test_invalid_uuid_member_id_returns_422(self, api: httpx.Client) -> None:
        resp = api.get(
            "/api/v1/streak",
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
            "/api/v1/streak",
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
        """auth.verify_gym_employee_for_member 404s on an unknown member
        before the streak service runs — intentional, not a bug."""
        resp = api.get(
            "/api/v1/streak",
            params={"member_id": str(uuid4()), "gym_id": GYM_ID},
        )
        assert resp.status_code == 404, resp.text


# ---------------------------------------------------------------------------
# Regression: streak weeks bucket in the GYM's local timezone, not UTC
# ---------------------------------------------------------------------------


class TestStreakWeekBoundaryIsGymLocal:
    """Founder-confirmed bug: a late Sunday-evening class in the gym's
    timezone must land in that Sunday's GYM-LOCAL week, even though its UTC
    instant already spills onto the following Monday. Exercises the real
    ``streak_weeks.sql`` (via a live DB session) plus the full
    ``StreakService`` pipeline (the Python current-week anchor must also be
    gym-local)."""

    def test_late_sunday_gym_local_buckets_into_the_previous_gym_local_week(
        self, seed_ids: dict
    ) -> None:
        member_row = seed_ids["attendance_free_member"]
        class_id = seed_ids["any_class_id"]
        tz_name = seed_ids["gym_timezone"]
        if member_row is None or class_id is None or tz_name is None:
            pytest.skip(
                "Seed missing an attendance-free member / class / gym timezone"
            )
        member_id = str(member_row["member_id"])
        class_id = str(class_id)
        gym_tz = ZoneInfo(tz_name)

        # This week's gym-local Monday, and the Sunday that ends the
        # PREVIOUS gym-local week.
        today_gym = datetime.now(UTC).astimezone(gym_tz).date()
        current_monday = today_gym - timedelta(days=today_gym.weekday())
        previous_monday = current_monday - timedelta(days=7)
        target_sunday = current_monday - timedelta(days=1)

        occurred_at_local = datetime.combine(
            target_sunday, time(23, 0), tzinfo=gym_tz
        )
        occurred_at_utc = occurred_at_local.astimezone(UTC)
        # Sanity: this is exactly the scenario the founder flagged -- the
        # gym-local instant's UTC calendar date has already rolled to the
        # following (Monday) date. If this ever fails, the seeded gym's
        # timezone offset changed and this test needs re-anchoring.
        assert occurred_at_utc.date() == current_monday

        _insert_raw_attendance(
            member_id, class_id, target_sunday, time(23, 0), occurred_at_utc
        )
        try:

            async def _run_checks() -> tuple[set[date], int]:
                pool = DirectDatabasePool()
                try:
                    sql = load_sql(SQL_DIR / "streak_weeks.sql")
                    async with pool.session() as session:
                        rows = (
                            await session.execute(
                                text(sql),
                                {"member_id": member_id, "gym_id": GYM_ID},
                            )
                        ).all()
                    week_starts = {row[0] for row in rows}
                    streak = await StreakService(pool).get_streak(
                        UUID(member_id), UUID(GYM_ID)
                    )
                    return week_starts, streak
                finally:
                    await pool.engine.dispose()

            week_starts, streak = _run_async(_run_checks())

            # Gym-local bucketing: the Sunday-evening attendance belongs to
            # the week that STARTED the previous Monday -- NOT a UTC-derived
            # bucket keyed to the instant's UTC calendar date.
            assert week_starts == {previous_monday}
            # The full pipeline (Python current-week anchor + the SQL
            # bucket) must agree: exactly a 1-week streak, anchored off
            # "last week" gym-locally.
            assert streak == 1
        finally:
            _delete_raw_attendance(member_id, class_id, target_sunday)


# ---------------------------------------------------------------------------
# GET /api/v1/checkin/history — the attended row carries the class's points
# ---------------------------------------------------------------------------


def _class_with_current_schedule() -> dict | None:
    """A class that has a CURRENT schedule version + its ``points_worth``.

    The history query joins ``gym_class_schedules_current``, so a class with
    no live version would be dropped; discovering through that same join
    guarantees the inserted attendance row surfaces.
    """

    async def _run() -> dict | None:
        conn = await asyncpg.connect(_get_db_url())
        try:
            row = await conn.fetchrow(
                "SELECT c.class_id, c.points_worth FROM gym_classes c "
                "JOIN gym_class_schedules_current s ON s.class_id = c.class_id "
                "WHERE c.gym_id = $1 LIMIT 1",
                UUID(GYM_ID),
            )
            return dict(row) if row is not None else None
        finally:
            await conn.close()

    return _run_async(_run())


class TestClassHistoryPointsWorth:
    """The member-page history card reads ``points_worth`` off the class row,
    so the post-class celebration can show "+N points earned". Regression
    lock: ``checkin_member_history.sql`` must SELECT ``gym_classes.points_worth``
    and ``CheckinHistoryService`` must map it onto the row."""

    def test_attended_history_row_carries_class_points_worth(
        self, api: httpx.Client, seed_ids: dict
    ) -> None:
        member_row = seed_ids["attendance_free_member"]
        klass = _class_with_current_schedule()
        if member_row is None or klass is None:
            pytest.skip(
                "Seed missing an attendance-free member / scheduled class"
            )
        member_id = str(member_row["member_id"])
        class_id = str(klass["class_id"])
        expected_points = int(klass["points_worth"])

        original_date = date.today() - timedelta(days=30)
        original_time = time(12, 0)
        occurred_at = datetime.combine(original_date, original_time, tzinfo=UTC)

        _insert_raw_attendance(
            member_id, class_id, original_date, original_time, occurred_at
        )
        try:
            resp = api.get(
                "/api/v1/checkin/history",
                params={"member_id": member_id, "gym_id": GYM_ID},
            )
            assert resp.status_code == 200, resp.text
            history = resp.json()["history"]
            mine = [
                r
                for r in history
                if r["class_id"] == class_id
                and r["original_date"] == original_date.isoformat()
                and r["status"] == "attended"
            ]
            assert len(mine) == 1, (
                "the inserted attended occurrence must appear exactly once "
                f"in history; got {mine}"
            )
            assert mine[0]["points_worth"] == expected_points
        finally:
            _delete_raw_attendance(member_id, class_id, original_date)
