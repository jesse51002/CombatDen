"""Live integration tests for sign-ups (reservations).

Endpoints under test:
  POST   /api/v1/signup
  DELETE /api/v1/signup
  GET    /api/v1/checkin/attendees   (the combined signed-up-or-attended roster)
  GET    /api/v1/classes/instances   (the schedule board's signup_count)
  POST   /api/v1/checkin             (the capacity gate reading the union)

These run against the live backend + the seeded DB, the same way
test_checkin_integration.py / test_classes_crud_integration.py do.

IMPORTANT: this file needs the versioned-schedule migration applied to the
shared local DB (``gym_class_schedules`` + the re-keyed ``class_signups`` /
``member_attendance`` with ``original_date`` / ``original_time`` columns).
Until the user runs the hand-written migration, every test in this file
fails with an ``UndefinedTableError`` / ``UndefinedColumnError`` / 500 —
that is a migration-not-applied gap, not a code defect (mirrors the note in
test_checkin_integration.py).

A dedicated class (max_capacity=1, daily recurring, spanning yesterday) is
created for the capacity tests so they don't depend on seeded classes'
capacities. ``occurrence_date`` is fixed to YESTERDAY (gym-local) so check-in
is always open (past occurrences never hit the "not open yet" window) without
racing the time-of-day the suite happens to run at; ``occurrence_time`` is
fixed to the class's single daily slot (``_OCCURRENCE_TIME``) — every
occurrence-addressed call now takes both (a class may occur several times
per day, so the date alone never identifies an occurrence).
"""

from __future__ import annotations

import asyncio
from datetime import date, datetime, time, timedelta
from uuid import UUID, uuid4
from zoneinfo import ZoneInfo

import asyncpg
import httpx
import pytest
from dotenv import dotenv_values

from tests.seed_constants import SEEDED_GYM_ID

GYM_ID = SEEDED_GYM_ID
CLASSES_BASE = "/api/v1/classes"

_ENV_PATH = "/var/home/jm/Documents/CombatDen/codebase/FastApiBackend/.env"
# The single daily slot every test class in this file is minted with — its
# ORIGINAL identity time, paired with occurrence_date on every request.
_OCCURRENCE_TIME = time(10, 0)


def _get_db_url() -> str:
    env = dotenv_values(_ENV_PATH)
    return env.get("DATABASE_URL", "").replace(
        "postgresql+asyncpg://", "postgresql://"
    )


def _run_async(coro):
    """Run a coroutine on a fresh loop (pytest owns the main loop)."""
    loop = asyncio.new_event_loop()
    try:
        return loop.run_until_complete(coro)
    finally:
        loop.close()


_MEMBERS_SQL = "SELECT member_id FROM members WHERE gym_id = $1 LIMIT 2"
_GYM_TZ_SQL = "SELECT timezone FROM gyms WHERE gym_id = $1"
_INSTRUCTOR_SQL = """
SELECT employee_id FROM gym_employees WHERE gym_id = $1 LIMIT 1
"""


@pytest.fixture(scope="session")
def seed() -> dict:
    """Discover two real member ids, an instructor, and the gym timezone."""

    async def _discover() -> dict:
        conn = await asyncpg.connect(_get_db_url())
        try:
            gym = UUID(GYM_ID)
            members = await conn.fetch(_MEMBERS_SQL, gym)
            return {
                "member_ids": [str(r["member_id"]) for r in members],
                "instructor_id": await conn.fetchval(_INSTRUCTOR_SQL, gym),
                "timezone": await conn.fetchval(_GYM_TZ_SQL, gym),
            }
        finally:
            await conn.close()

    try:
        ids = _run_async(_discover())
    except Exception as exc:  # noqa: BLE001 — any DB issue means skip, not fail
        pytest.skip(f"Seeded DB not reachable for discovery: {exc}")
    if len(ids["member_ids"]) < 2 or ids["instructor_id"] is None:
        pytest.skip("Need >=2 members + an instructor in the seeded gym")
    return ids


def _yesterday(gym_tz: str) -> date:
    return datetime.now(ZoneInfo(gym_tz)).date() - timedelta(days=1)


def _make_class_payload(seed: dict, *, max_capacity: int | None) -> dict:
    """A daily-recurring class spanning yesterday, with a fixed capacity.

    ``weekday_slots`` is the current (versioned-schedule) shape: for a
    daily/monthly recurrence every slot lives under the reserved ``"all"``
    key — see ``GymClassScheduleFields`` / the class-system-guide skill.
    """
    occurrence_date = _yesterday(seed["timezone"])
    instructor_id = str(seed["instructor_id"])
    return {
        "gym_id": GYM_ID,
        "class_name": f"ZZ Signup Test {uuid4().hex[:8]}",
        "duration_minutes": 30,
        "recurring_unit": "daily",
        "recurring_interval": 1,
        "weekday_slots": {
            "all": [
                {
                    "time": _OCCURRENCE_TIME.isoformat(),
                    "instructor_id": instructor_id,
                }
            ]
        },
        "start_date": (occurrence_date - timedelta(days=3)).isoformat(),
        "end_date": (occurrence_date + timedelta(days=3)).isoformat(),
        "max_capacity": max_capacity,
        "points_worth": 10,
    }


def _create_class(
    api: httpx.Client, tracked_class_ids: list[str], seed: dict, *, max_capacity: int | None
) -> str:
    resp = api.post(CLASSES_BASE, json=_make_class_payload(seed, max_capacity=max_capacity))
    assert resp.status_code == 201, resp.text
    class_id = resp.json()["class_id"]
    tracked_class_ids.append(class_id)
    return class_id


def _cleanup_classes(class_ids: list[str]) -> None:
    async def _run() -> None:
        conn = await asyncpg.connect(_get_db_url())
        try:
            for class_id in class_ids:
                cid = UUID(class_id)
                await conn.execute(
                    "DELETE FROM member_attendance WHERE class_id = $1", cid
                )
                await conn.execute(
                    "DELETE FROM class_signups WHERE class_id = $1", cid
                )
                await conn.execute(
                    "DELETE FROM gym_class_schedules WHERE class_id = $1", cid
                )
                await conn.execute(
                    "DELETE FROM gym_classes WHERE class_id = $1", cid
                )
        finally:
            await conn.close()

    _run_async(_run())


@pytest.fixture
def tracked_classes():
    class_ids: list[str] = []
    try:
        yield class_ids
    finally:
        _cleanup_classes(class_ids)


def _signup_count(
    class_id: str, occurrence_date: date, occurrence_time: time = _OCCURRENCE_TIME
) -> int:
    async def _run() -> int:
        conn = await asyncpg.connect(_get_db_url())
        try:
            return await conn.fetchval(
                "SELECT COUNT(*) FROM class_signups "
                "WHERE class_id = $1 AND original_date = $2 AND original_time = $3",
                UUID(class_id),
                occurrence_date,
                occurrence_time,
            )
        finally:
            await conn.close()

    return _run_async(_run())


# ---------------------------------------------------------------------------
# POST /api/v1/signup, DELETE /api/v1/signup
# ---------------------------------------------------------------------------


class TestSignupCreateRemove:
    def test_signup_then_idempotent_repeat_then_remove(
        self, api: httpx.Client, seed: dict, tracked_classes: list[str]
    ) -> None:
        """A fresh sign-up creates a row; a repeat is idempotent
        (already_signed_up=True, same signup_id, no extra row); DELETE removes
        it; a second DELETE is a no-op (removed=False)."""
        class_id = _create_class(api, tracked_classes, seed, max_capacity=None)
        occurrence_date = _yesterday(seed["timezone"])
        member_id = seed["member_ids"][0]
        params = {
            "member_id": member_id,
            "gym_id": GYM_ID,
            "class_id": class_id,
            "occurrence_date": occurrence_date.isoformat(),
            "occurrence_time": _OCCURRENCE_TIME.isoformat(),
        }

        first = api.post("/api/v1/signup", json=params)
        assert first.status_code == 200, first.text
        assert first.json()["already_signed_up"] is False
        signup_id = first.json()["signup_id"]
        assert _signup_count(class_id, occurrence_date) == 1

        second = api.post("/api/v1/signup", json=params)
        assert second.status_code == 200, second.text
        assert second.json()["already_signed_up"] is True
        assert second.json()["signup_id"] == signup_id
        assert _signup_count(class_id, occurrence_date) == 1  # no extra row

        removed = api.request("DELETE", "/api/v1/signup", params=params)
        assert removed.status_code == 200, removed.text
        assert removed.json()["removed"] is True
        assert _signup_count(class_id, occurrence_date) == 0

        again = api.request("DELETE", "/api/v1/signup", params=params)
        assert again.status_code == 200, again.text
        assert again.json()["removed"] is False

    def test_unlimited_capacity_always_ok(
        self, api: httpx.Client, seed: dict, tracked_classes: list[str]
    ) -> None:
        """A class with NULL max_capacity never rejects a sign-up."""
        class_id = _create_class(api, tracked_classes, seed, max_capacity=None)
        occurrence_date = _yesterday(seed["timezone"])

        for member_id in seed["member_ids"]:
            resp = api.post(
                "/api/v1/signup",
                json={
                    "member_id": member_id,
                    "gym_id": GYM_ID,
                    "class_id": class_id,
                    "occurrence_date": occurrence_date.isoformat(),
                    "occurrence_time": _OCCURRENCE_TIME.isoformat(),
                },
            )
            assert resp.status_code == 200, resp.text

        assert _signup_count(class_id, occurrence_date) == len(seed["member_ids"])

    def test_full_class_rejects_a_new_member(
        self, api: httpx.Client, seed: dict, tracked_classes: list[str]
    ) -> None:
        """max_capacity=1: the first sign-up succeeds, a second (different)
        member is rejected with 'Class is full'."""
        class_id = _create_class(api, tracked_classes, seed, max_capacity=1)
        occurrence_date = _yesterday(seed["timezone"])
        member_a, member_b = seed["member_ids"][0], seed["member_ids"][1]

        first = api.post(
            "/api/v1/signup",
            json={
                "member_id": member_a,
                "gym_id": GYM_ID,
                "class_id": class_id,
                "occurrence_date": occurrence_date.isoformat(),
                "occurrence_time": _OCCURRENCE_TIME.isoformat(),
            },
        )
        assert first.status_code == 200, first.text

        second = api.post(
            "/api/v1/signup",
            json={
                "member_id": member_b,
                "gym_id": GYM_ID,
                "class_id": class_id,
                "occurrence_date": occurrence_date.isoformat(),
                "occurrence_time": _OCCURRENCE_TIME.isoformat(),
            },
        )
        assert second.status_code == 400, second.text
        assert "full" in second.json()["detail"].lower()
        assert _signup_count(class_id, occurrence_date) == 1


# ---------------------------------------------------------------------------
# GET /api/v1/checkin/attendees — the combined roster
# ---------------------------------------------------------------------------


class TestCombinedRoster:
    def test_roster_flags_signed_up_and_attended_members_correctly(
        self, api: httpx.Client, seed: dict, tracked_classes: list[str]
    ) -> None:
        """A signed-up-only member, an attended-only member, and a member who
        is both are each flagged correctly in the combined roster."""
        class_id = _create_class(api, tracked_classes, seed, max_capacity=None)
        occurrence_date = _yesterday(seed["timezone"])
        signup_only, attend_and_signup = seed["member_ids"][0], seed["member_ids"][1]

        # signup_only: sign-up, no check-in.
        resp = api.post(
            "/api/v1/signup",
            json={
                "member_id": signup_only,
                "gym_id": GYM_ID,
                "class_id": class_id,
                "occurrence_date": occurrence_date.isoformat(),
                "occurrence_time": _OCCURRENCE_TIME.isoformat(),
            },
        )
        assert resp.status_code == 200, resp.text

        # attend_and_signup: sign up, then check in (staff override — no
        # membership needed to record).
        resp = api.post(
            "/api/v1/signup",
            json={
                "member_id": attend_and_signup,
                "gym_id": GYM_ID,
                "class_id": class_id,
                "occurrence_date": occurrence_date.isoformat(),
                "occurrence_time": _OCCURRENCE_TIME.isoformat(),
            },
        )
        assert resp.status_code == 200, resp.text
        checkin = api.post(
            "/api/v1/checkin",
            json={
                "member_id": attend_and_signup,
                "gym_id": GYM_ID,
                "class_id": class_id,
                "occurrence_date": occurrence_date.isoformat(),
                "occurrence_time": _OCCURRENCE_TIME.isoformat(),
                "ignore_warnings": True,
            },
        )
        assert checkin.status_code == 200, checkin.text

        roster = api.get(
            "/api/v1/checkin/attendees",
            params={
                "gym_id": GYM_ID,
                "class_id": class_id,
                "occurrence_date": occurrence_date.isoformat(),
                "occurrence_time": _OCCURRENCE_TIME.isoformat(),
            },
        )
        assert roster.status_code == 200, roster.text
        by_member = {a["member_id"]: a for a in roster.json()["attendees"]}

        assert by_member[signup_only]["signed_up"] is True
        assert by_member[signup_only]["attended"] is False
        assert by_member[signup_only]["log_id"] is None

        assert by_member[attend_and_signup]["signed_up"] is True
        assert by_member[attend_and_signup]["attended"] is True
        assert by_member[attend_and_signup]["log_id"] is not None


# ---------------------------------------------------------------------------
# GET /api/v1/classes/instances — the board's signup_count
# ---------------------------------------------------------------------------


class TestBoardSignupCount:
    def test_board_shows_signup_count_for_a_past_occurrence(
        self, api: httpx.Client, seed: dict, tracked_classes: list[str]
    ) -> None:
        class_id = _create_class(api, tracked_classes, seed, max_capacity=None)
        occurrence_date = _yesterday(seed["timezone"])

        resp = api.post(
            "/api/v1/signup",
            json={
                "member_id": seed["member_ids"][0],
                "gym_id": GYM_ID,
                "class_id": class_id,
                "occurrence_date": occurrence_date.isoformat(),
                "occurrence_time": _OCCURRENCE_TIME.isoformat(),
            },
        )
        assert resp.status_code == 200, resp.text

        board = api.get(
            f"{CLASSES_BASE}/instances",
            params={
                "gym_id": GYM_ID,
                "start_date": (occurrence_date - timedelta(days=1)).isoformat(),
                "end_date": (occurrence_date + timedelta(days=1)).isoformat(),
            },
        )
        assert board.status_code == 200, board.text
        by_date = {
            (row["class_id"], row["class_date"]): row for row in board.json()["items"]
        }
        row = by_date[(class_id, occurrence_date.isoformat())]
        assert row["signup_count"] == 1


# ---------------------------------------------------------------------------
# POST /api/v1/checkin — the capacity gate reads the signed-up-or-attended union
# ---------------------------------------------------------------------------


class TestCheckinCapacityUnion:
    def test_walk_in_blocked_once_signups_fill_the_room(
        self, api: httpx.Client, seed: dict, tracked_classes: list[str]
    ) -> None:
        """max_capacity=1: one member's sign-up fills the room; a second
        (uncovered) member's KIOSK check-in is rejected with
        skip_reason='over_capacity' — a sign-up alone reserves the spot."""
        class_id = _create_class(api, tracked_classes, seed, max_capacity=1)
        occurrence_date = _yesterday(seed["timezone"])
        member_a, member_b = seed["member_ids"][0], seed["member_ids"][1]

        signup = api.post(
            "/api/v1/signup",
            json={
                "member_id": member_a,
                "gym_id": GYM_ID,
                "class_id": class_id,
                "occurrence_date": occurrence_date.isoformat(),
                "occurrence_time": _OCCURRENCE_TIME.isoformat(),
            },
        )
        assert signup.status_code == 200, signup.text

        checkin = api.post(
            "/api/v1/checkin",
            json={
                "member_id": member_b,
                "gym_id": GYM_ID,
                "class_id": class_id,
                "occurrence_date": occurrence_date.isoformat(),
                "occurrence_time": _OCCURRENCE_TIME.isoformat(),
                "is_member": True,
            },
        )
        assert checkin.status_code == 200, checkin.text
        body = checkin.json()
        assert body["log_id"] is None
        assert body["skip_reason"] == "over_capacity"
