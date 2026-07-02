"""Live integration tests for the class CRUD + exception + board endpoints.

Endpoints under test (all gym-employee gated, hit on the live backend):
  GET    /api/v1/classes                 (list)
  POST   /api/v1/classes                 (create)
  GET    /api/v1/classes/{id}            (get)
  PUT    /api/v1/classes/{id}            (update)
  DELETE /api/v1/classes/{id}            (soft-delete)
  POST   /api/v1/classes/{id}/exceptions/instance  (upsert; reschedule + 409)
  POST   /api/v1/classes/{id}/exceptions/range     (create)
  GET    /api/v1/classes/instances       (schedule board)

Run against the live backend + the seeded DB; the suite DISCOVERS a real
instructor and a real membership from the DB and skips gracefully when the DB
isn't reachable. Everything created is tracked and deleted in FK-safe order on
teardown (the ``created`` fixture below), mirroring the conftest ``created``
pattern; seed data is never touched.

NOTE (versioned-schedule migration pending): the class system moved from a
materialized ``class_history`` + live ``gym_classes`` recurrence to APPEND-ONLY
``gym_class_schedules`` versions (``class_history`` dropped; ``gym_classes`` is
identity-only; ``member_attendance`` re-keyed to ``(class_id, original_date,
original_time)`` + a denormalized ``occurred_at``). The migration
(``Database/supabase/migrations/20260701020000_versioned_class_schedules.sql``)
may not be applied to the shared local DB yet — until it is, every endpoint in
this file 500s (``class_history`` / ``gym_class_schedules`` undefined) or the
create/update schema rejects the request. These tests assert the CORRECT
post-migration behavior and are EXPECTED to fail at runtime until the user runs
the migration — that is a missing migration, not a code defect.
"""

from __future__ import annotations

import asyncio
from datetime import UTC, date, datetime, time, timedelta
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

# A fixed, deterministic daily window (every date has an occurrence).
_START = date(2025, 1, 6)
_END = date(2025, 1, 12)
_CANCEL_DATE = date(2025, 1, 8)
_ATTEND_DATE = date(2025, 1, 9)
_RESCHEDULE_FROM = date(2025, 1, 10)
_RESCHEDULE_TO = date(2025, 1, 20)
_CLASS_TIME = time(9, 0)


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


_INSTRUCTOR_SQL = """
SELECT employee_id, first_name, last_name
FROM gym_employees WHERE gym_id = $1 LIMIT 1
"""

_MEMBERSHIP_SQL = """
SELECT item_id, member_id, plan_id
FROM member_memberships_unfiltered
WHERE gym_id = $1
LIMIT 1
"""

_GYM_TZ_SQL = "SELECT timezone FROM gyms WHERE gym_id = $1"


@pytest.fixture(scope="session")
def seed() -> dict:
    """Discover a real instructor, membership, and the gym timezone."""

    async def _discover() -> dict:
        conn = await asyncpg.connect(_get_db_url())
        try:
            gym = UUID(GYM_ID)
            return {
                "instructor": await conn.fetchrow(_INSTRUCTOR_SQL, gym),
                "membership": await conn.fetchrow(_MEMBERSHIP_SQL, gym),
                "timezone": await conn.fetchval(_GYM_TZ_SQL, gym),
            }
        finally:
            await conn.close()

    try:
        return _run_async(_discover())
    except Exception as exc:  # noqa: BLE001 — any DB issue means skip, not fail
        pytest.skip(f"Seeded DB not reachable for discovery: {exc}")


class _Created:
    """Tracks created class_ids and deletes everything tied to them."""

    def __init__(self) -> None:
        self.class_ids: list[str] = []

    def track_class(self, class_id: str) -> None:
        self.class_ids.append(class_id)

    def cleanup(self) -> None:
        async def _run() -> None:
            conn = await asyncpg.connect(_get_db_url())
            try:
                for class_id in self.class_ids:
                    cid = UUID(class_id)
                    # FK-safe order: rows keyed by class_id, then the
                    # versioned schedule history, then the identity row.
                    await conn.execute(
                        "DELETE FROM member_attendance WHERE class_id = $1",
                        cid,
                    )
                    await conn.execute(
                        "DELETE FROM class_signups WHERE class_id = $1", cid
                    )
                    await conn.execute(
                        "DELETE FROM class_instance_exceptions WHERE class_id = $1",
                        cid,
                    )
                    await conn.execute(
                        "DELETE FROM class_range_exceptions WHERE class_id = $1",
                        cid,
                    )
                    await conn.execute(
                        "DELETE FROM gym_class_schedules WHERE class_id = $1",
                        cid,
                    )
                    await conn.execute(
                        "DELETE FROM gym_classes WHERE class_id = $1", cid
                    )
            finally:
                await conn.close()

        _run_async(_run())


@pytest.fixture
def created() -> _Created:
    registry = _Created()
    try:
        yield registry
    finally:
        registry.cleanup()


def _make_class_payload(seed: dict) -> dict:
    """A daily-recurring class with one instructor on every weekday slot."""
    instructor_id = str(seed["instructor"]["employee_id"])
    payload = {
        "gym_id": GYM_ID,
        "class_name": f"ZZ CRUD Test {uuid4().hex[:8]}",
        "class_description": "integration test class",
        "class_time": _CLASS_TIME.isoformat(),
        "duration_minutes": 60,
        "recurring_unit": "daily",
        "recurring_interval": 1,
        "start_date": _START.isoformat(),
        "end_date": _END.isoformat(),
        "max_capacity": 20,
        "points_worth": 50,
    }
    for day in ("sun", "mon", "tue", "wed", "thu", "fri", "sat"):
        payload[f"{day}_instructor_id"] = instructor_id
    return payload


def _create_class(api: httpx.Client, created: _Created, seed: dict) -> dict:
    resp = api.post(CLASSES_BASE, json=_make_class_payload(seed))
    assert resp.status_code == 201, resp.text
    body = resp.json()
    created.track_class(body["class_id"])
    return body


# ---------------------------------------------------------------------------
# Class CRUD  (no migration dependency)
# ---------------------------------------------------------------------------


class TestClassCrud:
    def test_create_get_update_soft_delete_list(
        self, api: httpx.Client, created: _Created, seed: dict
    ) -> None:
        body = _create_class(api, created, seed)
        class_id = body["class_id"]
        assert body["gym_id"] == GYM_ID
        assert body["recurring_unit"] == "daily"
        assert body["is_active"] is True
        assert body["is_deleted"] is False
        # Instructor slots resolved to a display name.
        expected_name = (
            f"{seed['instructor']['first_name']} "
            f"{seed['instructor']['last_name']}"
        )
        assert body["mon_instructor_name"] == expected_name

        # GET round-trips the same row.
        got = api.get(f"{CLASSES_BASE}/{class_id}")
        assert got.status_code == 200, got.text
        assert got.json()["class_id"] == class_id

        # PUT splits by destination: `identity` (partial) updates gym_classes
        # in place; a provided value changes, an absent one is untouched, and
        # the untouched `schedule` (no mint) leaves duration_minutes alone.
        upd = api.put(
            f"{CLASSES_BASE}/{class_id}",
            json={
                "identity": {"class_name": "ZZ Renamed", "points_worth": 75}
            },
        )
        assert upd.status_code == 200, upd.text
        assert upd.json()["class_name"] == "ZZ Renamed"
        assert upd.json()["points_worth"] == 75
        assert upd.json()["duration_minutes"] == 60  # untouched (no schedule mint)

        # PUT with the `schedule` half (a COMPLETE shape) mints a new
        # version; the flattened read reflects the new current version.
        payload = _make_class_payload(seed)
        schedule = {
            key: value
            for key, value in payload.items()
            if key
            not in (
                "gym_id",
                "class_name",
                "class_description",
                "max_capacity",
                "points_worth",
            )
        }
        schedule["duration_minutes"] = 90
        upd2 = api.put(
            f"{CLASSES_BASE}/{class_id}", json={"schedule": schedule}
        )
        assert upd2.status_code == 200, upd2.text
        assert upd2.json()["duration_minutes"] == 90
        assert upd2.json()["class_name"] == "ZZ Renamed"  # identity untouched

        # DELETE soft-deletes.
        deleted = api.delete(f"{CLASSES_BASE}/{class_id}")
        assert deleted.status_code == 200, deleted.text
        assert deleted.json()["is_deleted"] is True
        assert deleted.json()["is_active"] is False

        # Default list excludes the soft-deleted class.
        listed = api.get(CLASSES_BASE, params={"gym_id": GYM_ID})
        assert listed.status_code == 200, listed.text
        ids = {item["class_id"] for item in listed.json()["items"]}
        assert class_id not in ids

    def test_create_weekly_without_a_day_returns_400(
        self, api: httpx.Client, seed: dict
    ) -> None:
        payload = _make_class_payload(seed)
        payload["recurring_unit"] = "weekly"  # no day flags set
        resp = api.post(CLASSES_BASE, json=payload)
        assert resp.status_code == 400, resp.text

    def test_get_unknown_class_returns_404(self, api: httpx.Client) -> None:
        resp = api.get(f"{CLASSES_BASE}/{uuid4()}")
        assert resp.status_code == 404, resp.text


# ---------------------------------------------------------------------------
# Range exceptions
# ---------------------------------------------------------------------------


class TestRangeExceptions:
    def test_create_range_exception(
        self, api: httpx.Client, created: _Created, seed: dict
    ) -> None:
        class_id = _create_class(api, created, seed)["class_id"]
        resp = api.post(
            f"{CLASSES_BASE}/{class_id}/exceptions/range",
            json={
                "start_date": _START.isoformat(),
                "end_date": _CANCEL_DATE.isoformat(),
                "is_cancelled": True,
            },
        )
        assert resp.status_code == 201, resp.text
        assert resp.json()["is_cancelled"] is True

    def test_range_exception_requires_cancel_or_instructor(
        self, api: httpx.Client, created: _Created, seed: dict
    ) -> None:
        class_id = _create_class(api, created, seed)["class_id"]
        resp = api.post(
            f"{CLASSES_BASE}/{class_id}/exceptions/range",
            json={
                "start_date": _START.isoformat(),
                "end_date": _END.isoformat(),
                "is_cancelled": False,
            },
        )
        assert resp.status_code == 400, resp.text


# ---------------------------------------------------------------------------
# Instance exceptions
# ---------------------------------------------------------------------------


class TestInstanceExceptions:
    def test_cancel_then_reschedule_then_conflict(
        self, api: httpx.Client, created: _Created, seed: dict
    ) -> None:
        class_id = _create_class(api, created, seed)["class_id"]
        base = f"{CLASSES_BASE}/{class_id}/exceptions/instance"

        # Cancel one occurrence.
        cancel = api.post(
            base, json={"original_date": _CANCEL_DATE.isoformat(), "is_cancelled": True}
        )
        assert cancel.status_code == 200, cancel.text
        assert cancel.json()["is_cancelled"] is True

        # Reschedule another occurrence to a free (non-class) date.
        reschedule = api.post(
            base,
            json={
                "original_date": _RESCHEDULE_FROM.isoformat(),
                "new_date": _RESCHEDULE_TO.isoformat(),
            },
        )
        assert reschedule.status_code == 200, reschedule.text
        assert reschedule.json()["new_date"] == _RESCHEDULE_TO.isoformat()

        # A second reschedule onto an in-window occurring date collides (409):
        # _ATTEND_DATE has a live daily occurrence.
        conflict = api.post(
            base,
            json={
                "original_date": _START.isoformat(),
                "new_date": _ATTEND_DATE.isoformat(),
            },
        )
        assert conflict.status_code == 409, conflict.text


# ---------------------------------------------------------------------------
# Schedule board
# ---------------------------------------------------------------------------


class TestScheduleBoard:
    def _insert_attendance(
        self, class_id: str, gym_tz: str, membership: asyncpg.Record
    ) -> None:
        """Record one attendance keyed by the _ATTEND_DATE original slot.

        Attendance is keyed by the occurrence's identity ``(class_id,
        original_date, original_time)`` with a denormalized ``occurred_at``
        (no class_history row exists anymore).
        """
        occurred_at = datetime.combine(
            _ATTEND_DATE, _CLASS_TIME, tzinfo=ZoneInfo(gym_tz)
        ).astimezone(UTC)

        async def _run() -> None:
            conn = await asyncpg.connect(_get_db_url())
            try:
                await conn.execute(
                    "INSERT INTO member_attendance "
                    "(member_id, gym_id, class_id, original_date, "
                    " original_time, occurred_at, plan_id, item_id) "
                    "VALUES ($1, $2, $3, $4, $5, $6, $7, $8)",
                    membership["member_id"],
                    UUID(GYM_ID),
                    UUID(class_id),
                    _ATTEND_DATE,
                    _CLASS_TIME,
                    occurred_at,
                    membership["plan_id"],
                    membership["item_id"],
                )
            finally:
                await conn.close()

        _run_async(_run())

    def test_board_shows_cancelled_day_and_attendance_count(
        self, api: httpx.Client, created: _Created, seed: dict
    ) -> None:
        if seed["membership"] is None:
            pytest.skip("No membership in seed to attribute attendance to")
        class_id = _create_class(api, created, seed)["class_id"]

        # Cancel _CANCEL_DATE.
        cancel = api.post(
            f"{CLASSES_BASE}/{class_id}/exceptions/instance",
            json={"original_date": _CANCEL_DATE.isoformat(), "is_cancelled": True},
        )
        assert cancel.status_code == 200, cancel.text

        # Record attendance against the _ATTEND_DATE occurrence.
        self._insert_attendance(class_id, seed["timezone"], seed["membership"])

        board = api.get(
            f"{CLASSES_BASE}/instances",
            params={
                "gym_id": GYM_ID,
                "start_date": _START.isoformat(),
                "end_date": _END.isoformat(),
            },
        )
        assert board.status_code == 200, board.text
        # Board rows carry the occurrence's IDENTITY date (original_date) —
        # what every occurrence-addressed call passes — alongside the
        # displayed class_date.
        by_date = {
            (row["class_id"], row["original_date"]): row
            for row in board.json()["items"]
        }

        cancelled_row = by_date[(class_id, _CANCEL_DATE.isoformat())]
        assert cancelled_row["is_cancelled"] is True
        assert cancelled_row["has_instance_exception"] is True
        assert cancelled_row["class_date"] == _CANCEL_DATE.isoformat()

        attended_row = by_date[(class_id, _ATTEND_DATE.isoformat())]
        assert attended_row["is_cancelled"] is False
        assert attended_row["attendance_count"] == 1


# ---------------------------------------------------------------------------
# Range-cancel teardown
# ---------------------------------------------------------------------------


class TestRangeExceptionTeardown:
    """A CANCEL range (``is_cancelled=True``) tears down the reservations +
    early check-ins of the dates it actually cancels, in the SAME
    transaction as the range insert — with the founder-approved asymmetry
    that an already-run (past-instant) occurrence keeps its attendance."""

    def _dynamic_class_payload(self, seed: dict, today: date) -> dict:
        """A daily-recurring class spanning past-to-future relative to the
        REAL current time (unlike the fixed 2025 window above, which is
        entirely in the past by the time this runs) — needed to exercise the
        instant-based future/past teardown split for real."""
        instructor_id = str(seed["instructor"]["employee_id"])
        payload = {
            "gym_id": GYM_ID,
            "class_name": f"ZZ Range Teardown Test {uuid4().hex[:8]}",
            "class_description": "range-cancel teardown test class",
            "class_time": _CLASS_TIME.isoformat(),
            "duration_minutes": 60,
            "recurring_unit": "daily",
            "recurring_interval": 1,
            "start_date": (today - timedelta(days=30)).isoformat(),
            "end_date": (today + timedelta(days=30)).isoformat(),
            "max_capacity": 20,
            "points_worth": 50,
        }
        for day in ("sun", "mon", "tue", "wed", "thu", "fri", "sat"):
            payload[f"{day}_instructor_id"] = instructor_id
        return payload

    def _insert_signup(
        self, class_id: str, member_id: UUID, occurrence_date: date
    ) -> None:
        async def _run() -> None:
            conn = await asyncpg.connect(_get_db_url())
            try:
                await conn.execute(
                    "INSERT INTO class_signups "
                    "(gym_id, class_id, member_id, original_date, original_time) "
                    "VALUES ($1, $2, $3, $4, $5)",
                    UUID(GYM_ID),
                    UUID(class_id),
                    member_id,
                    occurrence_date,
                    _CLASS_TIME,
                )
            finally:
                await conn.close()

        _run_async(_run())

    def _insert_attendance_for(
        self,
        class_id: str,
        occurrence_date: date,
        gym_tz: str,
        membership: asyncpg.Record,
    ) -> None:
        occurred_at = datetime.combine(
            occurrence_date, _CLASS_TIME, tzinfo=ZoneInfo(gym_tz)
        ).astimezone(UTC)

        async def _run() -> None:
            conn = await asyncpg.connect(_get_db_url())
            try:
                await conn.execute(
                    "INSERT INTO member_attendance "
                    "(member_id, gym_id, class_id, original_date, "
                    " original_time, occurred_at, plan_id, item_id) "
                    "VALUES ($1, $2, $3, $4, $5, $6, $7, $8)",
                    membership["member_id"],
                    UUID(GYM_ID),
                    UUID(class_id),
                    occurrence_date,
                    _CLASS_TIME,
                    occurred_at,
                    membership["plan_id"],
                    membership["item_id"],
                )
            finally:
                await conn.close()

        _run_async(_run())

    def _signup_exists(self, class_id: str, occurrence_date: date) -> bool:
        async def _run() -> bool:
            conn = await asyncpg.connect(_get_db_url())
            try:
                row = await conn.fetchrow(
                    "SELECT 1 FROM class_signups "
                    "WHERE class_id = $1 AND original_date = $2",
                    UUID(class_id),
                    occurrence_date,
                )
                return row is not None
            finally:
                await conn.close()

        return _run_async(_run())

    def _attendance_exists(self, class_id: str, occurrence_date: date) -> bool:
        async def _run() -> bool:
            conn = await asyncpg.connect(_get_db_url())
            try:
                row = await conn.fetchrow(
                    "SELECT 1 FROM member_attendance "
                    "WHERE class_id = $1 AND original_date = $2",
                    UUID(class_id),
                    occurrence_date,
                )
                return row is not None
            finally:
                await conn.close()

        return _run_async(_run())

    def test_range_cancel_tears_down_future_keeps_override_and_past(
        self, api: httpx.Client, created: _Created, seed: dict
    ) -> None:
        if seed["membership"] is None:
            pytest.skip("No membership in seed to attribute attendance to")

        today = date.today()
        payload = self._dynamic_class_payload(seed, today)
        resp = api.post(CLASSES_BASE, json=payload)
        assert resp.status_code == 201, resp.text
        class_id = resp.json()["class_id"]
        created.track_class(class_id)

        future_covered = today + timedelta(days=5)
        override_protected = today + timedelta(days=10)
        past_covered = today - timedelta(days=5)
        range_start = today - timedelta(days=7)
        range_end = today + timedelta(days=14)

        member_id = seed["membership"]["member_id"]

        # A future covered date: a reservation + an early check-in (the 2h
        # check-in window) — both must be torn down.
        self._insert_signup(class_id, member_id, future_covered)
        self._insert_attendance_for(
            class_id, future_covered, seed["timezone"], seed["membership"]
        )

        # A covered date with a non-cancelled instance override — the range
        # can never apply to a date any instance exception governs.
        override = api.post(
            f"{CLASSES_BASE}/{class_id}/exceptions/instance",
            json={
                "original_date": override_protected.isoformat(),
                "new_class_time": "10:00:00",
            },
        )
        assert override.status_code == 200, override.text
        self._insert_signup(class_id, member_id, override_protected)

        # A past covered date that already ran and was attended — kept.
        self._insert_attendance_for(
            class_id, past_covered, seed["timezone"], seed["membership"]
        )

        # The range cancel — one transaction covering the insert + teardown.
        range_resp = api.post(
            f"{CLASSES_BASE}/{class_id}/exceptions/range",
            json={
                "start_date": range_start.isoformat(),
                "end_date": range_end.isoformat(),
                "is_cancelled": True,
            },
        )
        assert range_resp.status_code == 201, range_resp.text
        assert range_resp.json()["is_cancelled"] is True

        # Future covered date: torn down.
        assert self._signup_exists(class_id, future_covered) is False
        assert self._attendance_exists(class_id, future_covered) is False

        # Override-protected date: untouched (instance exception wins).
        assert self._signup_exists(class_id, override_protected) is True

        # Past covered date: attendance kept (the asymmetry).
        assert self._attendance_exists(class_id, past_covered) is True
