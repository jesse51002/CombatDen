"""Live integration tests for the occurrence undo (cancel) + reschedule
endpoints — Phase 6.

Endpoints under test (admin/owner gated, hit on the live backend):
  DELETE /api/v1/classes/{class_id}/occurrences/{occurrence_date}            (cancel)
  POST   /api/v1/classes/{class_id}/occurrences/{occurrence_date}/reschedule (move)

Run against the live backend + the seeded DB. The suite DISCOVERS a real
instructor, an unlimited membership (for the cancel-with-attendance case), and a
single-class pack plan (for the auto-end-reversal case), and skips gracefully
when the DB / required seed rows aren't available. Everything created — classes,
their lazily-materialized history + attendance + exceptions, the test pack
membership, and a probe activity — is tracked and deleted in FK-safe order on
teardown (the ``created`` fixture); seed data is never mutated.

NOTE (migration-blocked): the Phase-1 migration — ``class_instance_exceptions``
``new_date`` + the ``uq_class_history_occurrence`` UNIQUE (class_id, occurred_at)
— is NOT applied to the shared local DB yet. Until it is:
  * the reschedule endpoint (reads/writes ``new_date``) and any path that loads
    instance exceptions fail with an undefined-column error, and
  * the lazy materializer's ``ON CONFLICT ON CONSTRAINT
    uq_class_history_occurrence`` has no constraint to target.
These tests assert the CORRECT post-migration behavior and are EXPECTED to fail
at runtime until the migration lands — that is a missing migration, not a code
defect. They are written against the right behavior, never reshaped to pass.
"""

from __future__ import annotations

import asyncio
import json
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

# A fixed, deterministic daily window (every date in it has an occurrence).
_START = date(2025, 1, 6)
_END = date(2025, 1, 12)
_ATTEND_DATE = date(2025, 1, 9)
_PACK_DATE = date(2025, 1, 8)
_MATERIALIZED_DATE = date(2025, 1, 7)
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
SELECT employee_id FROM gym_employees WHERE gym_id = $1 LIMIT 1
"""

# An unlimited (recurring, class_count NULL) membership: attendance against it is
# never an auto-end pack, so cancelling leaves memberships_unended empty.
_UNLIMITED_MEMBERSHIP_SQL = """
SELECT ms.item_id, ms.member_id, ms.plan_id
FROM member_memberships_unfiltered ms
JOIN membership_plans_unfiltered mp ON mp.plan_id = ms.plan_id
WHERE ms.gym_id = $1
  AND mp.class_count IS NULL
LIMIT 1
"""

# A single-class pack plan (trial / one_time, class_count = 1) + an active price,
# so ONE attendance depletes a quantity-1 membership on it (capacity = 1).
_PACK_PLAN_SQL = """
SELECT mp.plan_id, pr.price_id
FROM membership_plans_unfiltered mp
JOIN membership_plan_prices_unfiltered pr
    ON pr.plan_id = mp.plan_id AND pr.is_active = TRUE
WHERE mp.gym_id = $1
  AND mp.plan_type IN ('trial', 'one_time')
  AND mp.class_count = 1
  AND mp.is_deleted = FALSE
LIMIT 1
"""

_ANY_MEMBER_SQL = "SELECT member_id FROM members WHERE gym_id = $1 LIMIT 1"
_GYM_TZ_SQL = "SELECT timezone FROM gyms WHERE gym_id = $1"


@pytest.fixture(scope="session")
def seed() -> dict:
    """Discover the rows the undo tests need; skip if the DB isn't reachable."""

    async def _discover() -> dict:
        conn = await asyncpg.connect(_get_db_url())
        try:
            gym = UUID(GYM_ID)
            return {
                "instructor": await conn.fetchrow(_INSTRUCTOR_SQL, gym),
                "unlimited": await conn.fetchrow(_UNLIMITED_MEMBERSHIP_SQL, gym),
                "pack_plan": await conn.fetchrow(_PACK_PLAN_SQL, gym),
                "member": await conn.fetchrow(_ANY_MEMBER_SQL, gym),
                "timezone": await conn.fetchval(_GYM_TZ_SQL, gym),
            }
        finally:
            await conn.close()

    try:
        return _run_async(_discover())
    except Exception as exc:  # noqa: BLE001 — any DB issue means skip, not fail
        pytest.skip(f"Seeded DB not reachable for discovery: {exc}")


class _Created:
    """Tracks created classes / memberships / activities and deletes them."""

    def __init__(self) -> None:
        self.class_ids: list[str] = []
        self.membership_item_ids: list[str] = []
        self.activity_ids: list[str] = []

    def track_class(self, class_id: str) -> None:
        self.class_ids.append(class_id)

    def track_membership(self, item_id: str) -> None:
        self.membership_item_ids.append(item_id)

    def track_activity(self, activity_id: str) -> None:
        self.activity_ids.append(activity_id)

    def cleanup(self) -> None:
        async def _run() -> None:
            conn = await asyncpg.connect(_get_db_url())
            try:
                for class_id in self.class_ids:
                    cid = UUID(class_id)
                    await conn.execute(
                        "DELETE FROM member_attendance WHERE class_history_id IN "
                        "(SELECT class_history_id FROM class_history "
                        "WHERE class_id = $1)",
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
                # Memberships after the class-tied attendance is gone (FK-safe).
                for item_id in self.membership_item_ids:
                    await conn.execute(
                        "DELETE FROM member_memberships_unfiltered "
                        "WHERE item_id = $1",
                        UUID(item_id),
                    )
                if self.activity_ids:
                    await conn.execute(
                        "DELETE FROM member_activities WHERE activity_id = ANY($1)",
                        [UUID(a) for a in self.activity_ids],
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


# -- shared helpers ---------------------------------------------------------


def _make_class_payload(seed: dict) -> dict:
    """A daily-recurring class over [_START, _END] with one instructor."""
    instructor_id = str(seed["instructor"]["employee_id"])
    payload = {
        "gym_id": GYM_ID,
        "class_name": f"ZZ Undo Test {uuid4().hex[:8]}",
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


def _create_class(api: httpx.Client, created: _Created, seed: dict) -> str:
    resp = api.post(CLASSES_BASE, json=_make_class_payload(seed))
    assert resp.status_code == 201, resp.text
    class_id = resp.json()["class_id"]
    created.track_class(class_id)
    return class_id


def _occurred_at(occ_date: date, gym_tz: str) -> datetime:
    return datetime.combine(
        occ_date, _CLASS_TIME, tzinfo=ZoneInfo(gym_tz)
    ).astimezone(UTC)


async def _materialize_with_attendance(
    class_id: str,
    gym_tz: str,
    occ_date: date,
    member_id: UUID,
    plan_id: UUID,
    item_id: UUID,
) -> str:
    """Insert a class_history row for the date + one attendance; return its id."""
    conn = await asyncpg.connect(_get_db_url())
    try:
        history_id = await conn.fetchval(
            "INSERT INTO class_history "
            "(class_id, gym_id, occurred_at, duration_minutes) "
            "VALUES ($1, $2, $3, $4) RETURNING class_history_id",
            UUID(class_id),
            UUID(GYM_ID),
            _occurred_at(occ_date, gym_tz),
            60,
        )
        await conn.execute(
            "INSERT INTO member_attendance "
            "(member_id, gym_id, class_history_id, plan_id, item_id) "
            "VALUES ($1, $2, $3, $4, $5)",
            member_id,
            UUID(GYM_ID),
            history_id,
            plan_id,
            item_id,
        )
        return str(history_id)
    finally:
        await conn.close()


def _db_scalar(query: str, *args):
    async def _run():
        conn = await asyncpg.connect(_get_db_url())
        try:
            return await conn.fetchval(query, *args)
        finally:
            await conn.close()

    return _run_async(_run())


# ---------------------------------------------------------------------------
# DELETE — cancel (un-occur)
# ---------------------------------------------------------------------------


class TestCancelOccurrence:
    def test_cancel_with_attendance_deletes_rows_and_reverts_points(
        self, api: httpx.Client, created: _Created, seed: dict
    ) -> None:
        """Cancelling an occurrence with attendance removes the attendance + the
        class_history row, writes the cancelled exception, and claws back each
        attendee's points (floored at 0) + drops a class_attended activity."""
        membership = seed["unlimited"]
        if membership is None:
            pytest.skip("No unlimited membership in seed to attribute attendance")
        member_id = membership["member_id"]
        class_id = _create_class(api, created, seed)

        history_id = _run_async(
            _materialize_with_attendance(
                class_id,
                seed["timezone"],
                _ATTEND_DATE,
                member_id,
                membership["plan_id"],
                membership["item_id"],
            )
        )

        # A probe class_attended activity for the class — the cancel claws it back.
        activity_id = _db_scalar(
            "INSERT INTO member_activities "
            "(member_id, gym_id, activity_type, activity_info) "
            "VALUES ($1, $2, 'class_attended', $3) RETURNING activity_id",
            member_id,
            UUID(GYM_ID),
            json.dumps({"class_id": class_id}),
        )
        created.track_activity(str(activity_id))

        before_points = _db_scalar(
            "SELECT points_balance FROM members WHERE member_id = $1", member_id
        )

        resp = api.delete(
            f"{CLASSES_BASE}/{class_id}/occurrences/{_ATTEND_DATE.isoformat()}",
            params={"gym_id": GYM_ID},
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["class_history_id"] == history_id
        assert body["attendance_rows_deleted"] == 1
        assert body["memberships_unended"] == []

        # Attendance + history gone.
        assert (
            _db_scalar(
                "SELECT COUNT(*) FROM member_attendance "
                "WHERE class_history_id = $1",
                UUID(history_id),
            )
            == 0
        )
        assert (
            _db_scalar(
                "SELECT COUNT(*) FROM class_history WHERE class_history_id = $1",
                UUID(history_id),
            )
            == 0
        )
        # Cancelled exception written for the date.
        assert (
            _db_scalar(
                "SELECT is_cancelled FROM class_instance_exceptions "
                "WHERE class_id = $1 AND original_date = $2",
                UUID(class_id),
                _ATTEND_DATE,
            )
            is True
        )
        # Points clawed back (the class's points_worth, floored at 0) and the
        # class_attended activity dropped — best-effort: the only one for this
        # freshly-created class is our probe.
        points_worth = _db_scalar(
            "SELECT points_worth FROM gym_classes WHERE class_id = $1",
            UUID(class_id),
        )
        assert (
            _db_scalar(
                "SELECT points_balance FROM members WHERE member_id = $1",
                member_id,
            )
            == max(before_points - points_worth, 0)
        )
        assert (
            _db_scalar(
                "SELECT COUNT(*) FROM member_activities WHERE activity_id = $1",
                activity_id,
            )
            == 0
        )

    def test_cancel_unmaterialized_writes_only_the_exception(
        self, api: httpx.Client, created: _Created, seed: dict
    ) -> None:
        """Cancelling a never-materialized occurrence writes just the cancelled
        exception: class_history_id null, nothing deleted."""
        class_id = _create_class(api, created, seed)

        resp = api.delete(
            f"{CLASSES_BASE}/{class_id}/occurrences/{_ATTEND_DATE.isoformat()}",
            params={"gym_id": GYM_ID},
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["class_history_id"] is None
        assert body["attendance_rows_deleted"] == 0
        assert body["memberships_unended"] == []
        assert (
            _db_scalar(
                "SELECT is_cancelled FROM class_instance_exceptions "
                "WHERE class_id = $1 AND original_date = $2",
                UUID(class_id),
                _ATTEND_DATE,
            )
            is True
        )

    def test_cancel_unknown_class_returns_404(
        self, api: httpx.Client
    ) -> None:
        resp = api.delete(
            f"{CLASSES_BASE}/{uuid4()}/occurrences/{_ATTEND_DATE.isoformat()}",
            params={"gym_id": GYM_ID},
        )
        assert resp.status_code == 404, resp.text


# ---------------------------------------------------------------------------
# DELETE — auto-end reversal (the depletion recompute)
# ---------------------------------------------------------------------------


class TestAutoEndReversal:
    async def _insert_pack_membership(
        self, member_id: UUID, plan_id: UUID, price_id: UUID
    ) -> str:
        """A depleted-shaped one_time pack: quantity 1, end_date already set."""
        conn = await asyncpg.connect(_get_db_url())
        try:
            item_id = await conn.fetchval(
                "INSERT INTO member_memberships_unfiltered "
                "(member_id, gym_id, plan_id, price_id, paid_by_member_id, "
                " start_date, end_date, total_price, quantity) "
                "VALUES ($1, $2, $3, $4, $1, $5, $6, 0, 1) RETURNING item_id",
                member_id,
                UUID(GYM_ID),
                plan_id,
                price_id,
                _START,
                _PACK_DATE,
            )
            return str(item_id)
        finally:
            await conn.close()

    def test_cancel_reverses_auto_end_on_depleted_pack(
        self, api: httpx.Client, created: _Created, seed: dict
    ) -> None:
        """A class_count=1 one_time pack, depleted (end_date set) by its single
        attendance, gets its end_date cleared when that class is un-occurred."""
        pack = seed["pack_plan"]
        member_row = seed["member"]
        if pack is None or member_row is None:
            pytest.skip("No single-class pack plan / member in seed")
        member_id = member_row["member_id"]

        item_id = _run_async(
            self._insert_pack_membership(
                member_id, pack["plan_id"], pack["price_id"]
            )
        )
        created.track_membership(item_id)

        class_id = _create_class(api, created, seed)
        history_id = _run_async(
            _materialize_with_attendance(
                class_id,
                seed["timezone"],
                _PACK_DATE,
                member_id,
                pack["plan_id"],
                UUID(item_id),
            )
        )

        # Sanity: the pack starts ended (depleted).
        assert (
            _db_scalar(
                "SELECT end_date FROM member_memberships_unfiltered "
                "WHERE item_id = $1",
                UUID(item_id),
            )
            == _PACK_DATE
        )

        resp = api.delete(
            f"{CLASSES_BASE}/{class_id}/occurrences/{_PACK_DATE.isoformat()}",
            params={"gym_id": GYM_ID},
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["class_history_id"] == history_id
        assert body["attendance_rows_deleted"] == 1
        assert body["memberships_unended"] == [item_id]

        # end_date cleared — the pack is active again.
        assert (
            _db_scalar(
                "SELECT end_date FROM member_memberships_unfiltered "
                "WHERE item_id = $1",
                UUID(item_id),
            )
            is None
        )


# ---------------------------------------------------------------------------
# POST — reschedule
# ---------------------------------------------------------------------------


class TestRescheduleOccurrence:
    def test_reschedule_to_free_date(
        self, api: httpx.Client, created: _Created, seed: dict
    ) -> None:
        class_id = _create_class(api, created, seed)
        resp = api.post(
            f"{CLASSES_BASE}/{class_id}/occurrences/"
            f"{_RESCHEDULE_FROM.isoformat()}/reschedule",
            json={"gym_id": GYM_ID, "new_date": _RESCHEDULE_TO.isoformat()},
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["original_date"] == _RESCHEDULE_FROM.isoformat()
        assert body["new_date"] == _RESCHEDULE_TO.isoformat()
        assert body["class_id"] == class_id

    def test_reschedule_onto_occupied_date_conflicts(
        self, api: httpx.Client, created: _Created, seed: dict
    ) -> None:
        """Moving onto an in-window occurring date is a 409 (collision)."""
        class_id = _create_class(api, created, seed)
        resp = api.post(
            f"{CLASSES_BASE}/{class_id}/occurrences/"
            f"{_START.isoformat()}/reschedule",
            json={"gym_id": GYM_ID, "new_date": _ATTEND_DATE.isoformat()},
        )
        assert resp.status_code == 409, resp.text

    def test_reschedule_already_materialized_conflicts(
        self, api: httpx.Client, created: _Created, seed: dict
    ) -> None:
        """An occurrence that already has a class_history row cannot be moved —
        cancel it first (409)."""
        membership = seed["unlimited"]
        if membership is None:
            pytest.skip("No membership in seed to materialize against")
        class_id = _create_class(api, created, seed)
        _run_async(
            _materialize_with_attendance(
                class_id,
                seed["timezone"],
                _MATERIALIZED_DATE,
                membership["member_id"],
                membership["plan_id"],
                membership["item_id"],
            )
        )
        resp = api.post(
            f"{CLASSES_BASE}/{class_id}/occurrences/"
            f"{_MATERIALIZED_DATE.isoformat()}/reschedule",
            json={"gym_id": GYM_ID, "new_date": date(2025, 1, 21).isoformat()},
        )
        assert resp.status_code == 409, resp.text

    def test_reschedule_earlier_date_returns_400(
        self, api: httpx.Client, created: _Created, seed: dict
    ) -> None:
        class_id = _create_class(api, created, seed)
        resp = api.post(
            f"{CLASSES_BASE}/{class_id}/occurrences/"
            f"{_RESCHEDULE_FROM.isoformat()}/reschedule",
            json={"gym_id": GYM_ID, "new_date": _START.isoformat()},
        )
        assert resp.status_code == 400, resp.text

    def test_reschedule_unknown_class_returns_404(
        self, api: httpx.Client
    ) -> None:
        resp = api.post(
            f"{CLASSES_BASE}/{uuid4()}/occurrences/"
            f"{_RESCHEDULE_FROM.isoformat()}/reschedule",
            json={"gym_id": GYM_ID, "new_date": _RESCHEDULE_TO.isoformat()},
        )
        assert resp.status_code == 404, resp.text
