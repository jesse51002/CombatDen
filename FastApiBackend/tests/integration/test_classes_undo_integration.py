"""Live integration tests for the occurrence undo (cancel) + reschedule
endpoints, plus the same-date override's attendance ``occurred_at`` re-sync.

Endpoints under test (admin/owner gated, hit on the live backend):
  DELETE /api/v1/classes/{class_id}/occurrences/{occurrence_date}            (cancel)
  POST   /api/v1/classes/{class_id}/occurrences/{occurrence_date}/reschedule (move)
  POST   /api/v1/classes/{class_id}/exceptions/instance   (reschedule + same-date override)

``occurrence_date`` is always the occurrence's ORIGINAL date — the identity
key ``(class_id, original_date, original_time)`` attendance and sign-ups are
stored under. Attendance lives directly on ``member_attendance`` keyed by
that slot (there is no ``class_history``); the denormalized ``occurred_at``
is re-synced by the keep paths (same-date override / reschedule-to-today-past)
and is the value the streak / cycle / last-class window SQL reads.

Run against the live backend + the seeded DB. The suite DISCOVERS a real
instructor (plus a SECOND, distinct instructor for the re-instructor cases),
an unlimited membership (for the cancel-with-attendance case), and a
single-class pack plan (for the auto-end-reversal case), and skips gracefully
when the DB / required seed rows aren't available. Everything created —
classes, their attendance + sign-ups + exceptions + schedule versions, the
test pack membership, and a probe activity — is tracked and deleted in
FK-safe order on teardown (the ``created`` fixture); seed data is never
mutated.

NOTE (versioned-schedule migration pending): the class system moved to
append-only ``gym_class_schedules`` versions (``class_history`` dropped;
``member_attendance`` re-keyed by original slot). The migration
(``Database/supabase/migrations/20260701020000_versioned_class_schedules.sql``)
may not be applied to the shared local DB yet — until it is, these endpoints
fail at runtime (undefined table/column). The tests assert the CORRECT
post-migration behavior and are EXPECTED to fail until the user runs the
migration — a missing migration, not a code defect.
"""

from __future__ import annotations

import asyncio
import json
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

# A fixed, deterministic daily window (every date in it has an occurrence).
_START = date(2025, 1, 6)
_END = date(2025, 1, 12)
_ATTEND_DATE = date(2025, 1, 9)
_PACK_DATE = date(2025, 1, 8)
_ATTENDED_PAST_DATE = date(2025, 1, 7)
_RESCHEDULE_FROM = date(2025, 1, 10)
_RESCHEDULE_TO = date(2025, 1, 20)
# Free (outside the class window) target dates for the attendance-move cases.
_KEEP_TO = date(2025, 1, 20)  # past target -> keeps + re-syncs occurred_at
_FUTURE_TO = date(2027, 6, 1)  # future target -> wipes the check-ins
_EARLIER_TO = date(2025, 1, 3)  # before the original -> accepted (any date)
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
SELECT employee_id FROM gym_employees WHERE gym_id = $1
ORDER BY employee_id LIMIT 1
"""

# A SECOND, distinct instructor (same deterministic ORDER BY as
# ``_INSTRUCTOR_SQL`` so the two never collide) — needed to prove a
# re-instructor override actually changed the effective instructor, not just
# re-wrote the same id.
_INSTRUCTOR2_SQL = """
SELECT employee_id FROM gym_employees WHERE gym_id = $1
ORDER BY employee_id OFFSET 1 LIMIT 1
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
                "instructor2": await conn.fetchrow(_INSTRUCTOR2_SQL, gym),
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
    """A daily-recurring class over [_START, _END] with one instructor on its
    single "all" slot."""
    instructor_id = str(seed["instructor"]["employee_id"])
    return {
        "gym_id": GYM_ID,
        "class_name": f"ZZ Undo Test {uuid4().hex[:8]}",
        "class_description": "integration test class",
        "duration_minutes": 60,
        "recurring_unit": "daily",
        "recurring_interval": 1,
        "weekday_slots": {
            "all": [
                {
                    "time": _CLASS_TIME.isoformat(),
                    "instructor_id": instructor_id,
                }
            ]
        },
        "start_date": _START.isoformat(),
        "end_date": _END.isoformat(),
        "max_capacity": 20,
        "points_worth": 50,
    }


def _create_class(api: httpx.Client, created: _Created, seed: dict) -> str:
    resp = api.post(CLASSES_BASE, json=_make_class_payload(seed))
    assert resp.status_code == 201, resp.text
    class_id = resp.json()["class_id"]
    created.track_class(class_id)
    return class_id


def _occurred_at(occ_date: date, gym_tz: str, at: time = _CLASS_TIME) -> datetime:
    return datetime.combine(
        occ_date, at, tzinfo=ZoneInfo(gym_tz)
    ).astimezone(UTC)


async def _insert_attendance(
    class_id: str,
    gym_tz: str,
    occ_date: date,
    member_id: UUID,
    plan_id: UUID,
    item_id: UUID,
) -> None:
    """Record one attendance keyed by the occurrence's ORIGINAL slot."""
    conn = await asyncpg.connect(_get_db_url())
    try:
        await conn.execute(
            "INSERT INTO member_attendance "
            "(member_id, gym_id, class_id, original_date, original_time, "
            " occurred_at, plan_id, item_id) "
            "VALUES ($1, $2, $3, $4, $5, $6, $7, $8)",
            member_id,
            UUID(GYM_ID),
            UUID(class_id),
            occ_date,
            _CLASS_TIME,
            _occurred_at(occ_date, gym_tz),
            plan_id,
            item_id,
        )
    finally:
        await conn.close()


async def _insert_signup(
    class_id: str, occ_date: date, member_id: UUID
) -> None:
    """Reserve the occurrence for the member (keyed by the original slot)."""
    conn = await asyncpg.connect(_get_db_url())
    try:
        await conn.execute(
            "INSERT INTO class_signups "
            "(gym_id, class_id, member_id, original_date, original_time) "
            "VALUES ($1, $2, $3, $4, $5)",
            UUID(GYM_ID),
            UUID(class_id),
            member_id,
            occ_date,
            _CLASS_TIME,
        )
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


def _attendance_count(class_id: str, occ_date: date) -> int:
    return _db_scalar(
        "SELECT COUNT(*) FROM member_attendance "
        "WHERE class_id = $1 AND original_date = $2",
        UUID(class_id),
        occ_date,
    )


def _attendance_occurred_at(class_id: str, occ_date: date) -> datetime | None:
    return _db_scalar(
        "SELECT occurred_at FROM member_attendance "
        "WHERE class_id = $1 AND original_date = $2",
        UUID(class_id),
        occ_date,
    )


def _signup_count(class_id: str, occ_date: date) -> int:
    return _db_scalar(
        "SELECT COUNT(*) FROM class_signups "
        "WHERE class_id = $1 AND original_date = $2",
        UUID(class_id),
        occ_date,
    )


# ---------------------------------------------------------------------------
# DELETE — cancel (un-occur)
# ---------------------------------------------------------------------------


class TestCancelOccurrence:
    def test_cancel_with_attendance_deletes_rows_and_reverts_points(
        self, api: httpx.Client, created: _Created, seed: dict
    ) -> None:
        """Cancelling an occurrence with attendance + a sign-up removes the
        attendance rows AND the occurrence's sign-ups, writes the cancelled
        exception, and claws back each attendee's points (floored at 0) +
        drops a class_attended activity."""
        membership = seed["unlimited"]
        if membership is None:
            pytest.skip("No unlimited membership in seed to attribute attendance")
        member_id = membership["member_id"]
        class_id = _create_class(api, created, seed)

        _run_async(
            _insert_attendance(
                class_id,
                seed["timezone"],
                _ATTEND_DATE,
                member_id,
                membership["plan_id"],
                membership["item_id"],
            )
        )
        # A reservation on the same occurrence — cancel must delete it too.
        _run_async(_insert_signup(class_id, _ATTEND_DATE, member_id))

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
            params={"gym_id": GYM_ID, "occurrence_time": _CLASS_TIME.isoformat()},
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["occurrence_date"] == _ATTEND_DATE.isoformat()
        assert body["occurrence_time"] == _CLASS_TIME.isoformat()
        assert body["attendance_rows_deleted"] == 1
        assert body["signups_deleted"] == 1
        assert body["memberships_unended"] == []

        # Attendance + sign-ups gone (keyed by the original slot).
        assert _attendance_count(class_id, _ATTEND_DATE) == 0
        assert _signup_count(class_id, _ATTEND_DATE) == 0
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

    def test_cancel_unattended_writes_only_the_exception(
        self, api: httpx.Client, created: _Created, seed: dict
    ) -> None:
        """Cancelling an occurrence nobody attended or reserved writes just
        the cancelled exception: nothing deleted."""
        class_id = _create_class(api, created, seed)

        resp = api.delete(
            f"{CLASSES_BASE}/{class_id}/occurrences/{_ATTEND_DATE.isoformat()}",
            params={"gym_id": GYM_ID, "occurrence_time": _CLASS_TIME.isoformat()},
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["attendance_rows_deleted"] == 0
        assert body["signups_deleted"] == 0
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
            params={"gym_id": GYM_ID, "occurrence_time": _CLASS_TIME.isoformat()},
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
        _run_async(
            _insert_attendance(
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
            params={"gym_id": GYM_ID, "occurrence_time": _CLASS_TIME.isoformat()},
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
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
            params={"occurrence_time": _CLASS_TIME.isoformat()},
            json={"gym_id": GYM_ID, "new_date": _RESCHEDULE_TO.isoformat()},
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["original_date"] == _RESCHEDULE_FROM.isoformat()
        assert body["original_time"] == _CLASS_TIME.isoformat()
        assert body["new_date"] == _RESCHEDULE_TO.isoformat()
        assert body["class_id"] == class_id

    def test_reschedule_onto_occupied_date_conflicts(
        self, api: httpx.Client, created: _Created, seed: dict
    ) -> None:
        """Moving onto an in-window occurring date (same start time) is a
        409 — the exact target instant is already taken."""
        class_id = _create_class(api, created, seed)
        resp = api.post(
            f"{CLASSES_BASE}/{class_id}/occurrences/"
            f"{_START.isoformat()}/reschedule",
            params={"occurrence_time": _CLASS_TIME.isoformat()},
            json={"gym_id": GYM_ID, "new_date": _ATTEND_DATE.isoformat()},
        )
        assert resp.status_code == 409, resp.text

    def test_reschedule_attended_past_keeps_and_resyncs_occurred_at(
        self, api: httpx.Client, created: _Created, seed: dict
    ) -> None:
        """An attended PAST occurrence moved to a free past date KEEPS its
        attendance (identity key unchanged) with the denormalized
        ``occurred_at`` re-synced onto the move's effective instant (no wipe,
        no 409). Sign-ups also carry — a reschedule never touches them."""
        membership = seed["unlimited"]
        if membership is None:
            pytest.skip("No membership in seed to attribute attendance to")
        class_id = _create_class(api, created, seed)
        _run_async(
            _insert_attendance(
                class_id,
                seed["timezone"],
                _ATTENDED_PAST_DATE,
                membership["member_id"],
                membership["plan_id"],
                membership["item_id"],
            )
        )
        _run_async(
            _insert_signup(
                class_id, _ATTENDED_PAST_DATE, membership["member_id"]
            )
        )
        resp = api.post(
            f"{CLASSES_BASE}/{class_id}/occurrences/"
            f"{_ATTENDED_PAST_DATE.isoformat()}/reschedule",
            params={"occurrence_time": _CLASS_TIME.isoformat()},
            json={"gym_id": GYM_ID, "new_date": _KEEP_TO.isoformat()},
        )
        assert resp.status_code == 200, resp.text
        assert resp.json()["new_date"] == _KEEP_TO.isoformat()
        # Attendance kept under its ORIGINAL slot key, occurred_at re-synced
        # onto the new effective instant.
        assert _attendance_count(class_id, _ATTENDED_PAST_DATE) == 1
        assert _attendance_occurred_at(
            class_id, _ATTENDED_PAST_DATE
        ) == _occurred_at(_KEEP_TO, seed["timezone"])
        # The sign-up carried (identity key untouched).
        assert _signup_count(class_id, _ATTENDED_PAST_DATE) == 1

    def test_reschedule_unknown_class_returns_404(
        self, api: httpx.Client
    ) -> None:
        resp = api.post(
            f"{CLASSES_BASE}/{uuid4()}/occurrences/"
            f"{_RESCHEDULE_FROM.isoformat()}/reschedule",
            params={"occurrence_time": _CLASS_TIME.isoformat()},
            json={"gym_id": GYM_ID, "new_date": _RESCHEDULE_TO.isoformat()},
        )
        assert resp.status_code == 404, resp.text


# ---------------------------------------------------------------------------
# POST /exceptions/instance — the CRM's single-request move (attendance follows)
# ---------------------------------------------------------------------------


class TestRescheduleAttendance:
    """The CRM's ``POST /exceptions/instance`` reschedule (``new_date`` set)
    moves the occurrence AND its attendance atomically, per the locked rule:
    a FUTURE target wipes the check-ins (points clawed back); a today / PAST
    target keeps them with ``occurred_at`` re-synced. Sign-ups always carry
    (the occurrence's identity key never changes)."""

    def _move(
        self,
        api: httpx.Client,
        class_id: str,
        original_date: date,
        new_date: date,
        new_instructor_id: str | None = None,
    ) -> httpx.Response:
        payload = {
            "original_date": original_date.isoformat(),
            "original_time": _CLASS_TIME.isoformat(),
            "new_date": new_date.isoformat(),
        }
        if new_instructor_id is not None:
            payload["new_instructor_id"] = new_instructor_id
        return api.post(
            f"{CLASSES_BASE}/{class_id}/exceptions/instance",
            json=payload,
        )

    def test_move_to_past_keeps_and_resyncs_occurred_at(
        self, api: httpx.Client, created: _Created, seed: dict
    ) -> None:
        """A PAST target keeps the check-ins under their original slot key,
        with ``occurred_at`` re-synced onto the move's effective instant."""
        membership = seed["unlimited"]
        if membership is None:
            pytest.skip("No unlimited membership in seed")
        class_id = _create_class(api, created, seed)
        _run_async(
            _insert_attendance(
                class_id,
                seed["timezone"],
                _ATTEND_DATE,
                membership["member_id"],
                membership["plan_id"],
                membership["item_id"],
            )
        )

        resp = self._move(api, class_id, _ATTEND_DATE, _KEEP_TO)
        assert resp.status_code == 200, resp.text
        assert resp.json()["new_date"] == _KEEP_TO.isoformat()

        # Same identity key, attendance kept, occurred_at re-synced.
        assert _attendance_count(class_id, _ATTEND_DATE) == 1
        assert _attendance_occurred_at(
            class_id, _ATTEND_DATE
        ) == _occurred_at(_KEEP_TO, seed["timezone"])

    def test_move_to_past_with_instructor_change_resolves_on_the_board(
        self, api: httpx.Client, created: _Created, seed: dict
    ) -> None:
        """A today/PAST reschedule that ALSO changes the instructor: the
        attendance keeps its key with ``occurred_at`` re-synced, the override
        row stores the new instructor, and the board resolves the moved
        occurrence to the NEW instructor (there is no snapshot to sync —
        instructor resolution happens at read time from the exception)."""
        membership = seed["unlimited"]
        instructor2 = seed["instructor2"]
        if membership is None or instructor2 is None:
            pytest.skip(
                "Need an unlimited membership + a second instructor in seed"
            )
        class_id = _create_class(api, created, seed)
        _run_async(
            _insert_attendance(
                class_id,
                seed["timezone"],
                _ATTEND_DATE,
                membership["member_id"],
                membership["plan_id"],
                membership["item_id"],
            )
        )
        new_instructor_id = str(instructor2["employee_id"])

        resp = self._move(
            api,
            class_id,
            _ATTEND_DATE,
            _KEEP_TO,
            new_instructor_id=new_instructor_id,
        )
        assert resp.status_code == 200, resp.text
        assert resp.json()["new_date"] == _KEEP_TO.isoformat()
        assert resp.json()["new_instructor_id"] == new_instructor_id

        # Attendance kept + re-synced.
        assert _attendance_count(class_id, _ATTEND_DATE) == 1
        assert _attendance_occurred_at(
            class_id, _ATTEND_DATE
        ) == _occurred_at(_KEEP_TO, seed["timezone"])

        # The board (window covering both the original and target dates)
        # renders the moved occurrence keyed by its ORIGINAL date, displayed
        # on the new date, resolved to the NEW instructor, count intact.
        board = api.get(
            f"{CLASSES_BASE}/instances",
            params={
                "gym_id": GYM_ID,
                "start_date": _START.isoformat(),
                "end_date": _KEEP_TO.isoformat(),
            },
        )
        assert board.status_code == 200, board.text
        moved = next(
            row
            for row in board.json()["items"]
            if row["class_id"] == class_id
            and row["original_date"] == _ATTEND_DATE.isoformat()
        )
        assert moved["class_date"] == _KEEP_TO.isoformat()
        assert moved["resolved_instructor_id"] == new_instructor_id
        assert moved["attendance_count"] == 1

    def test_move_to_future_wipes_and_reverts_points(
        self, api: httpx.Client, created: _Created, seed: dict
    ) -> None:
        """A FUTURE target wipes the moved occurrence's check-ins: attendance
        deleted, points clawed back (floored at 0), class_attended activity
        dropped — while the sign-ups still carry (never wiped by a
        reschedule)."""
        membership = seed["unlimited"]
        if membership is None:
            pytest.skip("No unlimited membership in seed")
        member_id = membership["member_id"]
        class_id = _create_class(api, created, seed)
        _run_async(
            _insert_attendance(
                class_id,
                seed["timezone"],
                _ATTEND_DATE,
                member_id,
                membership["plan_id"],
                membership["item_id"],
            )
        )
        _run_async(_insert_signup(class_id, _ATTEND_DATE, member_id))
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

        resp = self._move(api, class_id, _ATTEND_DATE, _FUTURE_TO)
        assert resp.status_code == 200, resp.text
        assert resp.json()["new_date"] == _FUTURE_TO.isoformat()

        # Attendance wiped; the sign-up carried.
        assert _attendance_count(class_id, _ATTEND_DATE) == 0
        assert _signup_count(class_id, _ATTEND_DATE) == 1
        # Points clawed back (floored at 0) + the class_attended activity dropped.
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

    def test_move_to_later_today_wipes_by_instant_not_day(
        self, api: httpx.Client, created: _Created, seed: dict
    ) -> None:
        """The wipe/keep decision is INSTANT-based, never day-based: moving
        an attended occurrence to TODAY at a time still ahead of now is a
        move to a class that hasn't happened — its check-ins wipe (the
        same-day 'keep' shortcut was the bug: a move past the check-in
        window but on the same calendar day silently kept attendance).
        Reservations carry either way."""
        membership = seed["unlimited"]
        if membership is None:
            pytest.skip("No unlimited membership in seed")
        local_now = datetime.now(ZoneInfo(seed["timezone"]))
        target_local = local_now + timedelta(hours=3)
        if target_local.date() != local_now.date():
            pytest.skip("Too close to gym-local midnight for a same-day move")
        member_id = membership["member_id"]
        class_id = _create_class(api, created, seed)
        _run_async(
            _insert_attendance(
                class_id,
                seed["timezone"],
                _ATTEND_DATE,
                member_id,
                membership["plan_id"],
                membership["item_id"],
            )
        )
        _run_async(_insert_signup(class_id, _ATTEND_DATE, member_id))

        resp = api.post(
            f"{CLASSES_BASE}/{class_id}/exceptions/instance",
            json={
                "original_date": _ATTEND_DATE.isoformat(),
                "original_time": _CLASS_TIME.isoformat(),
                "new_date": local_now.date().isoformat(),
                "new_class_time": target_local.time().replace(
                    microsecond=0
                ).isoformat(),
            },
        )
        assert resp.status_code == 200, resp.text

        # Same calendar day, future instant -> the check-in is wiped; the
        # reservation carries.
        assert _attendance_count(class_id, _ATTEND_DATE) == 0
        assert _signup_count(class_id, _ATTEND_DATE) == 1

    def test_move_to_earlier_today_keeps_by_instant(
        self, api: httpx.Client, created: _Created, seed: dict
    ) -> None:
        """The mirror case: a same-day target whose instant already PASSED
        keeps the check-ins (re-synced onto the new instant)."""
        membership = seed["unlimited"]
        if membership is None:
            pytest.skip("No unlimited membership in seed")
        local_now = datetime.now(ZoneInfo(seed["timezone"]))
        target_local = local_now - timedelta(hours=3)
        if target_local.date() != local_now.date():
            pytest.skip("Too close to gym-local midnight for a same-day move")
        member_id = membership["member_id"]
        class_id = _create_class(api, created, seed)
        _run_async(
            _insert_attendance(
                class_id,
                seed["timezone"],
                _ATTEND_DATE,
                member_id,
                membership["plan_id"],
                membership["item_id"],
            )
        )

        resp = api.post(
            f"{CLASSES_BASE}/{class_id}/exceptions/instance",
            json={
                "original_date": _ATTEND_DATE.isoformat(),
                "original_time": _CLASS_TIME.isoformat(),
                "new_date": local_now.date().isoformat(),
                "new_class_time": target_local.time().replace(
                    microsecond=0
                ).isoformat(),
            },
        )
        assert resp.status_code == 200, resp.text
        assert _attendance_count(class_id, _ATTEND_DATE) == 1

    def test_move_to_earlier_date_accepted(
        self, api: httpx.Client, created: _Created, seed: dict
    ) -> None:
        """Any date is accepted — INCLUDING new_date < original_date (the
        original date is only the anchor, not a lower bound)."""
        class_id = _create_class(api, created, seed)
        resp = self._move(api, class_id, _ATTEND_DATE, _EARLIER_TO)
        assert resp.status_code == 200, resp.text
        assert (
            _db_scalar(
                "SELECT new_date FROM class_instance_exceptions "
                "WHERE class_id = $1 AND original_date = $2",
                UUID(class_id),
                _ATTEND_DATE,
            )
            == _EARLIER_TO
        )


# ---------------------------------------------------------------------------
# POST /exceptions/instance — same-date override (new_date unset) re-syncs an
# ATTENDED occurrence's denormalized occurred_at
# ---------------------------------------------------------------------------


class TestOverrideAttendanceSync:
    """A same-date override (``new_date`` unset — retime / re-instructor /
    re-duration) on an ATTENDED occurrence re-syncs the attendance rows'
    denormalized ``occurred_at`` to the override's effective start instant,
    in the SAME transaction as the exception write. The override's duration /
    instructor resolve at read time from the exception row (nothing else is
    stored). An un-attended occurrence gets just the exception row."""

    def test_override_on_attended_occurrence_resyncs_occurred_at(
        self, api: httpx.Client, created: _Created, seed: dict
    ) -> None:
        """Retime + re-duration + re-instructor a PAST attended occurrence
        via the plain override (no ``new_date``): the attendance rows'
        ``occurred_at`` re-syncs to the override's effective instant (key
        unchanged, rows kept), and the board resolves the occurrence to the
        override's values with the count intact."""
        membership = seed["unlimited"]
        instructor2 = seed["instructor2"]
        if membership is None or instructor2 is None:
            pytest.skip(
                "Need an unlimited membership + a second instructor in seed"
            )
        class_id = _create_class(api, created, seed)
        _run_async(
            _insert_attendance(
                class_id,
                seed["timezone"],
                _ATTEND_DATE,
                membership["member_id"],
                membership["plan_id"],
                membership["item_id"],
            )
        )
        new_time = time(11, 30)
        new_duration = 90
        new_instructor_id = str(instructor2["employee_id"])

        resp = api.post(
            f"{CLASSES_BASE}/{class_id}/exceptions/instance",
            json={
                "original_date": _ATTEND_DATE.isoformat(),
                "original_time": _CLASS_TIME.isoformat(),
                "new_class_time": new_time.isoformat(),
                "new_duration_minutes": new_duration,
                "new_instructor_id": new_instructor_id,
            },
        )
        assert resp.status_code == 200, resp.text

        # Attendance kept under its key, occurred_at re-synced to the
        # override's effective instant.
        assert _attendance_count(class_id, _ATTEND_DATE) == 1
        assert _attendance_occurred_at(
            class_id, _ATTEND_DATE
        ) == _occurred_at(_ATTEND_DATE, seed["timezone"], new_time)

        # The board resolves the occurrence from the exception at read time.
        board = api.get(
            f"{CLASSES_BASE}/instances",
            params={
                "gym_id": GYM_ID,
                "start_date": _ATTEND_DATE.isoformat(),
                "end_date": _ATTEND_DATE.isoformat(),
            },
        )
        assert board.status_code == 200, board.text
        rows = [
            row for row in board.json()["items"] if row["class_id"] == class_id
        ]
        assert len(rows) == 1
        assert rows[0]["original_date"] == _ATTEND_DATE.isoformat()
        assert rows[0]["resolved_instructor_id"] == new_instructor_id
        assert rows[0]["resolved_duration_minutes"] == new_duration
        assert rows[0]["attendance_count"] == 1

    def test_override_on_unattended_occurrence_writes_only_exception(
        self, api: httpx.Client, created: _Created, seed: dict
    ) -> None:
        """A same-date override on an occurrence with NO attendance is a
        plain exception write — no attendance rows exist or appear; the
        override resolves at read time."""
        class_id = _create_class(api, created, seed)

        resp = api.post(
            f"{CLASSES_BASE}/{class_id}/exceptions/instance",
            json={
                "original_date": _ATTEND_DATE.isoformat(),
                "original_time": _CLASS_TIME.isoformat(),
                "new_class_time": "11:30:00",
                "new_duration_minutes": 90,
            },
        )
        assert resp.status_code == 200, resp.text
        assert (
            _db_scalar(
                "SELECT new_class_time FROM class_instance_exceptions "
                "WHERE class_id = $1 AND original_date = $2",
                UUID(class_id),
                _ATTEND_DATE,
            )
            == time(11, 30)
        )
        assert _attendance_count(class_id, _ATTEND_DATE) == 0
