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

NOTE: the Phase-1 migration (``class_instance_exceptions.new_date`` +
``uq_class_history_occurrence``) may not be applied to the shared local DB yet.
Until it is, every endpoint that reads/writes ``new_date`` — the instance
exception upsert/list and the schedule board (which loads instance exceptions) —
fails at runtime with an undefined-column error. The plain class CRUD and the
range-exception create do not depend on the migration and pass regardless.
"""

from __future__ import annotations

import asyncio
from datetime import UTC, date, datetime, time
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
                    await conn.execute(
                        "DELETE FROM member_attendance WHERE class_history_id IN "
                        "(SELECT class_history_id FROM class_history WHERE class_id = $1)",
                        cid,
                    )
                    await conn.execute(
                        "DELETE FROM class_history WHERE class_id = $1", cid
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

        # PUT updates mutable fields (a provided value changes; absent unchanged).
        upd = api.put(
            f"{CLASSES_BASE}/{class_id}",
            json={"data": {"class_name": "ZZ Renamed", "points_worth": 75}},
        )
        assert upd.status_code == 200, upd.text
        assert upd.json()["class_name"] == "ZZ Renamed"
        assert upd.json()["points_worth"] == 75
        assert upd.json()["duration_minutes"] == 60  # untouched

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
# Range exceptions  (no migration dependency)
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
# Instance exceptions  (depends on the new_date migration)
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
# Schedule board  (depends on the new_date migration)
# ---------------------------------------------------------------------------


class TestScheduleBoard:
    def _insert_history_and_attendance(
        self, class_id: str, gym_tz: str, membership: asyncpg.Record
    ) -> None:
        """Materialize a class_history row for _ATTEND_DATE + one attendance."""
        occurred_at = datetime.combine(
            _ATTEND_DATE, _CLASS_TIME, tzinfo=ZoneInfo(gym_tz)
        ).astimezone(UTC)

        async def _run() -> None:
            conn = await asyncpg.connect(_get_db_url())
            try:
                history_id = await conn.fetchval(
                    "INSERT INTO class_history "
                    "(class_id, gym_id, occurred_at, duration_minutes) "
                    "VALUES ($1, $2, $3, $4) RETURNING class_history_id",
                    UUID(class_id),
                    UUID(GYM_ID),
                    occurred_at,
                    60,
                )
                await conn.execute(
                    "INSERT INTO member_attendance "
                    "(member_id, gym_id, class_history_id, plan_id, item_id) "
                    "VALUES ($1, $2, $3, $4, $5)",
                    membership["member_id"],
                    UUID(GYM_ID),
                    history_id,
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
        self._insert_history_and_attendance(
            class_id, seed["timezone"], seed["membership"]
        )

        board = api.get(
            f"{CLASSES_BASE}/instances",
            params={
                "gym_id": GYM_ID,
                "start_date": _START.isoformat(),
                "end_date": _END.isoformat(),
            },
        )
        assert board.status_code == 200, board.text
        by_date = {
            (row["class_id"], row["class_date"]): row
            for row in board.json()["items"]
        }

        cancelled_row = by_date[(class_id, _CANCEL_DATE.isoformat())]
        assert cancelled_row["is_cancelled"] is True
        assert cancelled_row["has_instance_exception"] is True

        attended_row = by_date[(class_id, _ATTEND_DATE.isoformat())]
        assert attended_row["is_cancelled"] is False
        assert attended_row["attendance_count"] == 1
