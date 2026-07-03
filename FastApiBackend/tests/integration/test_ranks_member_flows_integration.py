"""Live integration tests for the member-rank + ladder-shape flows.

Endpoints under test (all new production rank paths):
  POST   /api/v1/ranks/promote-member    one rung up, audit-logged
  POST   /api/v1/ranks/set-member-rank   explicit set / unassign, audit-logged
  POST   /api/v1/ranks/reorder           full-ladder atomic reorder
  PUT    /api/v1/ranks/rename-group      atomic whole-group rename
  DELETE /api/v1/ranks/group             atomic whole-group delete
  PUT    /api/v1/ranks/enabled           false→true backfill (audit-logged)
  GET    /api/v1/members/{id}/billing    rank block + classes_since_rank

These run against the live backend + the seeded DB (same pattern as
tests/checkin/test_checkin_integration.py): suitable rows are DISCOVERED
at run time, never hard-coded, and every test restores exactly the state
it changed — member ranks are set back, created ranks are deleted, and
the ``rank_changed`` activity rows each flow writes are deleted by id.

The billing read here is the regression lock for the rank-progress
numerator: ``member_details.sql`` counts ``member_attendance`` on the
denormalized ``occurred_at`` (it once joined the dropped
``class_history`` table, which no mocked-DB unit test could catch).
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

RANKS_BASE = "/api/v1/ranks"
MEMBERS_BASE = "/api/v1/members"

_LADDER_SQL = """
SELECT rank_id, main_rank_num_order, sub_rank_num_order
FROM gym_ranks
WHERE gym_id = $1
ORDER BY main_rank_num_order ASC, sub_rank_num_order ASC
"""

_RANKED_MEMBERS_SQL = """
SELECT member_id, current_rank_id
FROM members
WHERE gym_id = $1
  AND current_rank_id IS NOT NULL
LIMIT 50
"""

_RANK_ACTIVITY_IDS_SQL = """
SELECT activity_id
FROM member_activities
WHERE member_id = $1
  AND gym_id = $2
  AND activity_type = 'rank_changed'
"""

_DELETE_ACTIVITIES_SQL = """
DELETE FROM member_activities WHERE activity_id = ANY($1)
"""

_MEMBER_RANK_SQL = """
SELECT current_rank_id FROM members WHERE member_id = $1
"""


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


async def _fetch(sql: str, *args):
    conn = await asyncpg.connect(_get_db_url())
    try:
        return await conn.fetch(sql, *args)
    finally:
        await conn.close()


async def _execute(sql: str, *args):
    conn = await asyncpg.connect(_get_db_url())
    try:
        return await conn.execute(sql, *args)
    finally:
        await conn.close()


@pytest.fixture(scope="module")
def ladder() -> list[dict]:
    """The seeded gym's ordered ladder, straight from the DB."""
    try:
        rows = _run_async(_fetch(_LADDER_SQL, UUID(GYM_ID)))
    except Exception as exc:  # pragma: no cover - env guard
        pytest.skip(f"DB not reachable: {exc}")
    if len(rows) < 2:
        pytest.skip("Seeded gym has fewer than 2 ranks")
    return [dict(r) for r in rows]


@pytest.fixture(scope="module")
def flow_member(ladder) -> dict:
    """A seeded member whose current rank is NOT the ladder top, so a
    promote has somewhere to go. Returns member_id + original rank."""
    rows = _run_async(_fetch(_RANKED_MEMBERS_SQL, UUID(GYM_ID)))
    top_rank_id = ladder[-1]["rank_id"]
    for row in rows:
        if row["current_rank_id"] != top_rank_id:
            return {
                "member_id": row["member_id"],
                "original_rank_id": row["current_rank_id"],
            }
    pytest.skip("No seeded member below the top rank")


class _ActivityJanitor:
    """Snapshot the member's rank_changed activity ids up front; on
    close, delete exactly the ids the flow added."""

    def __init__(self, member_id: UUID) -> None:
        self.member_id = member_id
        self.before = {
            r["activity_id"]
            for r in _run_async(
                _fetch(_RANK_ACTIVITY_IDS_SQL, member_id, UUID(GYM_ID)),
            )
        }

    def clean(self) -> None:
        after = {
            r["activity_id"]
            for r in _run_async(
                _fetch(_RANK_ACTIVITY_IDS_SQL, self.member_id, UUID(GYM_ID)),
            )
        }
        added = after - self.before
        if added:
            _run_async(_execute(_DELETE_ACTIVITIES_SQL, list(added)))


def _next_rank_id(ladder: list[dict], current_rank_id) -> str:
    ids = [r["rank_id"] for r in ladder]
    return str(ids[ids.index(current_rank_id) + 1])


def _set_member_rank(
    api: httpx.Client, member_id, rank_id: str | None
) -> httpx.Response:
    return api.post(
        f"{RANKS_BASE}/set-member-rank",
        json={
            "gym_id": GYM_ID,
            "member_id": str(member_id),
            "rank_id": rank_id,
        },
    )


# ---------------------------------------------------------------------------
# promote / set / unassign round trip (+ the billing numerator lock)
# ---------------------------------------------------------------------------


class TestMemberRankFlow:
    def test_promote_set_unassign_round_trip(
        self, api: httpx.Client, ladder: list[dict], flow_member: dict
    ) -> None:
        member_id = flow_member["member_id"]
        original = str(flow_member["original_rank_id"])
        expected_next = _next_rank_id(ladder, flow_member["original_rank_id"])

        janitor = _ActivityJanitor(member_id)
        try:
            # Promote: exactly one rung up the ordered ladder.
            resp = api.post(
                f"{RANKS_BASE}/promote-member",
                json={"gym_id": GYM_ID, "member_id": str(member_id)},
            )
            assert resp.status_code == 200, resp.text
            assert resp.json()["new_rank"]["rank_id"] == expected_next

            # The billing read must survive the live schema (regression:
            # the numerator once joined the dropped class_history table)
            # and the just-promoted member counts from the promotion —
            # zero classes since a promotion seconds ago.
            billing = api.get(f"{MEMBERS_BASE}/{member_id}/billing")
            assert billing.status_code == 200, billing.text
            rank_block = billing.json()["rank"]
            assert rank_block is not None
            assert rank_block["rank_id"] == expected_next
            assert rank_block["classes_since_rank"] == 0

            # Unassign (rank_id null) — allowed, returns no new_rank.
            resp = _set_member_rank(api, member_id, None)
            assert resp.status_code == 200, resp.text
            assert resp.json()["new_rank"] is None

            # Explicit set back to the original rank (the restore).
            resp = _set_member_rank(api, member_id, original)
            assert resp.status_code == 200, resp.text
            assert resp.json()["new_rank"]["rank_id"] == original

            row = _run_async(_fetch(_MEMBER_RANK_SQL, member_id))
            assert str(row[0]["current_rank_id"]) == original
        finally:
            # Belt-and-braces restore, then drop the audit rows added.
            _set_member_rank(api, member_id, original)
            janitor.clean()

    def test_promote_at_top_is_409(
        self, api: httpx.Client, ladder: list[dict], flow_member: dict
    ) -> None:
        member_id = flow_member["member_id"]
        original = str(flow_member["original_rank_id"])
        top = str(ladder[-1]["rank_id"])

        janitor = _ActivityJanitor(member_id)
        try:
            assert _set_member_rank(api, member_id, top).status_code == 200
            resp = api.post(
                f"{RANKS_BASE}/promote-member",
                json={"gym_id": GYM_ID, "member_id": str(member_id)},
            )
            assert resp.status_code == 409, resp.text
        finally:
            _set_member_rank(api, member_id, original)
            janitor.clean()

    def test_set_member_rank_wrong_gym_rank_is_404(
        self, api: httpx.Client, flow_member: dict
    ) -> None:
        """A rank_id that isn't a rank of the member's gym is rejected
        (resolved server-side, no member write happens)."""
        resp = _set_member_rank(api, flow_member["member_id"], str(uuid4()))
        assert resp.status_code == 404, resp.text


# ---------------------------------------------------------------------------
# reorder — identity payload exercises the two-phase update for real
# ---------------------------------------------------------------------------


class TestReorder:
    def test_identity_reorder_round_trips(
        self, api: httpx.Client, ladder: list[dict]
    ) -> None:
        """Submitting the CURRENT full ordering must succeed and leave
        the ladder unchanged — the shift/finalize dance runs against
        the real non-deferrable unique constraint."""
        payload = [
            {
                "rank_id": str(r["rank_id"]),
                "main_rank_num_order": r["main_rank_num_order"],
                "sub_rank_num_order": r["sub_rank_num_order"],
            }
            for r in ladder
        ]
        resp = api.post(
            f"{RANKS_BASE}/reorder",
            json={"gym_id": GYM_ID, "ranks": payload},
        )
        assert resp.status_code == 200, resp.text
        returned = [item["rank_id"] for item in resp.json()["items"]]
        assert returned == [str(r["rank_id"]) for r in ladder]

    def test_partial_payload_is_400(
        self, api: httpx.Client, ladder: list[dict]
    ) -> None:
        first = ladder[0]
        resp = api.post(
            f"{RANKS_BASE}/reorder",
            json={
                "gym_id": GYM_ID,
                "ranks": [
                    {
                        "rank_id": str(first["rank_id"]),
                        "main_rank_num_order": first["main_rank_num_order"],
                        "sub_rank_num_order": first["sub_rank_num_order"],
                    },
                ],
            },
        )
        assert resp.status_code == 400, resp.text
        assert "entire ladder" in resp.json()["detail"]


# ---------------------------------------------------------------------------
# whole-group rename + delete on a throwaway group
# ---------------------------------------------------------------------------


class TestGroupOps:
    def test_group_rename_and_delete_round_trip(
        self, api: httpx.Client, ladder: list[dict]
    ) -> None:
        """Create a temp group ABOVE the seed ladder, rename it
        atomically, then group-delete it — the seed is never touched
        (the temp group is never the backfill's lowest rank)."""
        new_main = max(r["main_rank_num_order"] for r in ladder) + 1
        created_ids: list[str] = []
        try:
            for sub, name in enumerate(["I", "II"]):
                resp = api.post(
                    f"{RANKS_BASE}/",
                    json={
                        "gym_id": GYM_ID,
                        "main_rank_num_order": new_main,
                        "sub_rank_num_order": sub,
                        "main_name": "Temp Test Group",
                        "sub_name": name,
                        "classes_till_rankup": 5,
                    },
                )
                assert resp.status_code == 201, resp.text
                created_ids.append(resp.json()["rank_id"])

            resp = api.put(
                f"{RANKS_BASE}/rename-group",
                json={
                    "gym_id": GYM_ID,
                    "main_rank_num_order": new_main,
                    "new_main_name": "Renamed Test Group",
                },
            )
            assert resp.status_code == 200, resp.text
            renamed = [
                item
                for item in resp.json()["items"]
                if item["rank_id"] in created_ids
            ]
            assert len(renamed) == 2
            assert all(
                item["main_name"] == "Renamed Test Group" for item in renamed
            )

            temp_ids = set(created_ids)
            resp = api.delete(
                f"{RANKS_BASE}/group",
                params={
                    "gym_id": GYM_ID,
                    "main_rank_num_order": new_main,
                },
            )
            assert resp.status_code == 204, resp.text
            created_ids.clear()

            listing = api.get(f"{RANKS_BASE}/", params={"gym_id": GYM_ID})
            assert listing.status_code == 200
            remaining = {item["rank_id"] for item in listing.json()["items"]}
            assert not remaining & temp_ids
        finally:
            # If the delete-group step never ran, remove stragglers.
            for rank_id in created_ids:
                api.delete(f"{RANKS_BASE}/{rank_id}")

    def test_delete_group_missing_is_404(self, api: httpx.Client) -> None:
        resp = api.delete(
            f"{RANKS_BASE}/group",
            params={"gym_id": GYM_ID, "main_rank_num_order": 999999},
        )
        assert resp.status_code == 404, resp.text


# ---------------------------------------------------------------------------
# enable-toggle backfill writes rank_changed audit rows
# ---------------------------------------------------------------------------


class TestEnableBackfillAudit:
    def test_backfill_assigns_lowest_and_logs_activity(
        self, api: httpx.Client, ladder: list[dict], flow_member: dict
    ) -> None:
        """Unassign a member, flip enabled false→true: the backfill
        must give them the LOWEST rank and write a rank_changed
        activity for it (the progress anchor starts at the backfill)."""
        member_id = flow_member["member_id"]
        original = str(flow_member["original_rank_id"])
        lowest = str(ladder[0]["rank_id"])

        janitor = _ActivityJanitor(member_id)
        try:
            assert _set_member_rank(api, member_id, None).status_code == 200

            for enabled in (False, True):
                resp = api.put(
                    f"{RANKS_BASE}/enabled",
                    json={"gym_id": GYM_ID, "is_rank_enabled": enabled},
                )
                assert resp.status_code == 200, resp.text

            row = _run_async(_fetch(_MEMBER_RANK_SQL, member_id))
            assert str(row[0]["current_rank_id"]) == lowest

            after = {
                r["activity_id"]
                for r in _run_async(
                    _fetch(_RANK_ACTIVITY_IDS_SQL, member_id, UUID(GYM_ID)),
                )
            }
            assert after - janitor.before, (
                "backfill wrote no rank_changed activity for the member"
            )
        finally:
            # Re-assert the seed's enabled state, restore the member's
            # rank, and drop every audit row this flow added.
            api.put(
                f"{RANKS_BASE}/enabled",
                json={"gym_id": GYM_ID, "is_rank_enabled": True},
            )
            _set_member_rank(api, member_id, original)
            janitor.clean()
