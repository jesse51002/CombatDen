"""Live integration tests for the member-rank + ladder-shape flows.

Two-level rank model: ``gym_ranks`` holds one row per MAIN rank; a member
is pinned to a leaf via ``current_rank_id`` + ``current_sub_index``. A rank
with ``sub_rank_count == 0`` is its own leaf (sub-index NULL); one with
``N >= 1`` has leaves ``0 .. N-1``.

Endpoints under test (all production rank paths):
  POST   /api/v1/ranks/promote-member       one leaf up, audit-logged
  POST   /api/v1/ranks/set-member-rank      explicit set / unassign, audit-logged
  POST   /api/v1/ranks/reorder              full-ladder atomic reorder
  PUT    /api/v1/ranks/enabled              false→true backfill (audit-logged)
  GET    /api/v1/ranks/ready-to-promote     paginated proximity board
  GET    /api/v1/ranks/{rank_id}/members    paginated rank roster
  GET    /api/v1/members/{id}/billing       rank block + classes_since_rank

These run against the live backend + the seeded DB (same pattern as
tests/integration/test_checkin_integration.py): suitable rows are DISCOVERED
at run time, never hard-coded, and every test restores exactly the state it
changed — member leaves are set back, created ranks are deleted, and the
``rank_changed`` activity rows each flow writes are deleted by id.

The billing read here is the regression lock for the rank-progress
numerator: ``member_details.sql`` counts ``member_attendance`` on the
denormalized ``occurred_at`` (it once joined the dropped ``class_history``
table, which no mocked-DB unit test could catch).
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
SELECT rank_id, main_rank_num_order, sub_rank_count
FROM gym_ranks
WHERE gym_id = $1
ORDER BY main_rank_num_order ASC
"""

_RANKED_MEMBERS_SQL = """
SELECT member_id, current_rank_id, current_sub_index
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

_MEMBER_LEAF_SQL = """
SELECT current_rank_id, current_sub_index FROM members WHERE member_id = $1
"""

_RANKLESS_MEMBERS_SQL = """
SELECT member_id
FROM members
WHERE gym_id = $1
  AND current_rank_id IS NULL
"""

_RESTORE_NULL_RANK_SQL = """
UPDATE members
SET current_rank_id = NULL, current_sub_index = NULL
WHERE member_id = $1
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


# ---------------------------------------------------------------------------
# leaf-advance rule (mirrors src.ranks.service.ranks_base.RanksBase._next_leaf)
# ---------------------------------------------------------------------------


def _base_leaf(rank: dict) -> int | None:
    """The base leaf of a main rank: 0 when it has sub-ranks, else None."""
    return 0 if rank["sub_rank_count"] > 0 else None


def _expected_next_leaf(
    ladder: list[dict], rank_id, sub_index: int | None
) -> tuple[object, int | None] | None:
    """The leaf a promotion should land on, or None when already at the top."""
    ids = [r["rank_id"] for r in ladder]
    if rank_id is None:
        return ladder[0]["rank_id"], _base_leaf(ladder[0])
    idx = ids.index(rank_id)
    cur = ladder[idx]
    if cur["sub_rank_count"] > 0:
        c = sub_index if sub_index is not None else -1
        if c < cur["sub_rank_count"] - 1:
            return cur["rank_id"], c + 1
    if idx >= len(ladder) - 1:
        return None  # highest leaf
    nxt = ladder[idx + 1]
    return nxt["rank_id"], _base_leaf(nxt)


def _top_leaf(ladder: list[dict]) -> tuple[object, int | None]:
    """The very top leaf: top main + its top sub-position (else NULL)."""
    top = ladder[-1]
    sub = top["sub_rank_count"] - 1 if top["sub_rank_count"] > 0 else None
    return top["rank_id"], sub


# ---------------------------------------------------------------------------
# fixtures
# ---------------------------------------------------------------------------


@pytest.fixture(scope="module")
def ladder() -> list[dict]:
    """The seeded gym's ordered ladder (main rows), straight from the DB."""
    try:
        rows = _run_async(_fetch(_LADDER_SQL, UUID(GYM_ID)))
    except Exception as exc:  # pragma: no cover - env guard
        pytest.skip(f"DB not reachable: {exc}")
    if len(rows) < 2:
        pytest.skip("Seeded gym has fewer than 2 ranks")
    return [dict(r) for r in rows]


@pytest.fixture(scope="module")
def flow_member(ladder) -> dict:
    """A seeded member whose current rank is NOT the top MAIN, so a promote
    always has somewhere to go. Returns member_id + original leaf."""
    rows = _run_async(_fetch(_RANKED_MEMBERS_SQL, UUID(GYM_ID)))
    top_rank_id = ladder[-1]["rank_id"]
    for row in rows:
        if row["current_rank_id"] != top_rank_id:
            return {
                "member_id": row["member_id"],
                "original_rank_id": row["current_rank_id"],
                "original_sub_index": row["current_sub_index"],
            }
    pytest.skip("No seeded member below the top main rank")


def _read_leaf(member_id) -> tuple[object, int | None]:
    """The member's current (rank_id, sub_index) straight from the DB."""
    row = _run_async(_fetch(_MEMBER_LEAF_SQL, member_id))[0]
    return row["current_rank_id"], row["current_sub_index"]


class _ActivityJanitor:
    """Snapshot the member's rank_changed activity ids up front; on close,
    delete exactly the ids the flow added."""

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


class _CollateralBackfillJanitor:
    """Cleanup for the members a gym-wide enable-backfill touches BESIDES
    the one under test.

    Flipping ``is_rank_enabled`` false→true backfills the lowest rank to
    EVERY rank-less member of the gym and writes each a ``rank_changed``
    row — not just ``flow_member``. This snapshots those other rank-less
    members (all currently NULL-ranked) plus their existing rank_changed
    activity ids up front; on close it restores each to rank-less (a direct
    UPDATE, so the restore itself writes no new activity) and deletes
    exactly the audit rows the backfill added for them. The member under
    test is excluded — the test restores that one to its seed leaf itself.
    """

    def __init__(self, exclude: UUID) -> None:
        self.members = [
            r["member_id"]
            for r in _run_async(_fetch(_RANKLESS_MEMBERS_SQL, UUID(GYM_ID)))
            if r["member_id"] != exclude
        ]
        self.before = {
            member_id: {
                r["activity_id"]
                for r in _run_async(
                    _fetch(_RANK_ACTIVITY_IDS_SQL, member_id, UUID(GYM_ID)),
                )
            }
            for member_id in self.members
        }

    def clean(self) -> None:
        added: list = []
        for member_id in self.members:
            after = {
                r["activity_id"]
                for r in _run_async(
                    _fetch(_RANK_ACTIVITY_IDS_SQL, member_id, UUID(GYM_ID)),
                )
            }
            added.extend(after - self.before[member_id])
            _run_async(_execute(_RESTORE_NULL_RANK_SQL, member_id))
        if added:
            _run_async(_execute(_DELETE_ACTIVITIES_SQL, added))


def _set_member_rank(
    api: httpx.Client, member_id, rank_id: str | None, sub_index: int | None = None
) -> httpx.Response:
    return api.post(
        f"{RANKS_BASE}/set-member-rank",
        json={
            "gym_id": GYM_ID,
            "member_id": str(member_id),
            "rank_id": rank_id,
            "sub_index": sub_index,
        },
    )


def _restore_leaf(api: httpx.Client, member_id, rank_id, sub_index) -> None:
    """Set the member back to a captured leaf (rank_id may be a UUID/str)."""
    _set_member_rank(
        api,
        member_id,
        str(rank_id) if rank_id is not None else None,
        sub_index,
    )


# ---------------------------------------------------------------------------
# promote / set / unassign round trip (+ the billing numerator lock)
# ---------------------------------------------------------------------------


class TestMemberRankFlow:
    def test_promote_set_unassign_round_trip(
        self, api: httpx.Client, ladder: list[dict], flow_member: dict
    ) -> None:
        member_id = flow_member["member_id"]
        original_rank = flow_member["original_rank_id"]
        original_sub = flow_member["original_sub_index"]

        rank_id, sub_index = _read_leaf(member_id)
        expected = _expected_next_leaf(ladder, rank_id, sub_index)
        assert expected is not None, "flow_member should be promotable"
        exp_rank, exp_sub = expected

        janitor = _ActivityJanitor(member_id)
        try:
            # Promote: exactly one leaf up the ordered ladder.
            resp = api.post(
                f"{RANKS_BASE}/promote-member",
                json={"gym_id": GYM_ID, "member_id": str(member_id)},
            )
            assert resp.status_code == 200, resp.text
            body = resp.json()
            assert body["new_rank"]["rank_id"] == str(exp_rank)
            assert body["new_sub_index"] == exp_sub

            # The billing read must survive the live schema (regression: the
            # numerator once joined the dropped class_history table) and the
            # just-promoted member counts from the promotion — zero classes
            # since a promotion seconds ago.
            billing = api.get(f"{MEMBERS_BASE}/{member_id}/billing")
            assert billing.status_code == 200, billing.text
            rank_block = billing.json()["rank"]
            assert rank_block is not None
            assert rank_block["rank_id"] == str(exp_rank)
            assert rank_block["sub_index"] == exp_sub
            assert rank_block["classes_since_rank"] == 0

            # Unassign (rank_id null) — allowed, returns no new_rank.
            resp = _set_member_rank(api, member_id, None)
            assert resp.status_code == 200, resp.text
            assert resp.json()["new_rank"] is None

            # Explicit set back to the original leaf (the restore).
            resp = _set_member_rank(
                api, member_id, str(original_rank), original_sub
            )
            assert resp.status_code == 200, resp.text
            assert resp.json()["new_rank"]["rank_id"] == str(original_rank)
            assert resp.json()["new_sub_index"] == original_sub

            db_rank, db_sub = _read_leaf(member_id)
            assert str(db_rank) == str(original_rank)
            assert db_sub == original_sub
        finally:
            _restore_leaf(api, member_id, original_rank, original_sub)
            janitor.clean()

    def test_sub_then_major_promotion(
        self, api: httpx.Client, ladder: list[dict], flow_member: dict
    ) -> None:
        """Promoting inside a sub-ranked main walks the sub positions, then
        crosses to the next main's base leaf at the top sub."""
        # A sub-ranked main that is NOT the top main (so a next major exists).
        sub_rank = next(
            (
                r
                for r in ladder[:-1]
                if r["sub_rank_count"] and r["sub_rank_count"] > 1
            ),
            None,
        )
        if sub_rank is None:
            pytest.skip("No non-top sub-ranked main to walk")

        member_id = flow_member["member_id"]
        original_rank = flow_member["original_rank_id"]
        original_sub = flow_member["original_sub_index"]
        idx = [r["rank_id"] for r in ladder].index(sub_rank["rank_id"])
        next_main = ladder[idx + 1]
        count = sub_rank["sub_rank_count"]

        janitor = _ActivityJanitor(member_id)
        try:
            assert (
                _set_member_rank(
                    api, member_id, str(sub_rank["rank_id"]), 0
                ).status_code
                == 200
            )
            # Walk each remaining sub position within the same main.
            for i in range(1, count):
                resp = api.post(
                    f"{RANKS_BASE}/promote-member",
                    json={"gym_id": GYM_ID, "member_id": str(member_id)},
                )
                assert resp.status_code == 200, resp.text
                body = resp.json()
                assert body["new_rank"]["rank_id"] == str(sub_rank["rank_id"])
                assert body["new_sub_index"] == i

            # At the top sub, the next promote crosses to the next main base.
            resp = api.post(
                f"{RANKS_BASE}/promote-member",
                json={"gym_id": GYM_ID, "member_id": str(member_id)},
            )
            assert resp.status_code == 200, resp.text
            body = resp.json()
            assert body["new_rank"]["rank_id"] == str(next_main["rank_id"])
            assert body["new_sub_index"] == _base_leaf(next_main)
        finally:
            _restore_leaf(api, member_id, original_rank, original_sub)
            janitor.clean()

    def test_set_member_rank_with_sub_index(
        self, api: httpx.Client, ladder: list[dict], flow_member: dict
    ) -> None:
        """set-member-rank onto a sub-ranked main pins the given leaf and
        returns the derived sub label."""
        sub_rank = next(
            (
                r
                for r in ladder
                if r["sub_rank_count"] and r["sub_rank_count"] > 1
            ),
            None,
        )
        if sub_rank is None:
            pytest.skip("No sub-ranked main in the seed")

        member_id = flow_member["member_id"]
        original_rank = flow_member["original_rank_id"]
        original_sub = flow_member["original_sub_index"]

        janitor = _ActivityJanitor(member_id)
        try:
            resp = _set_member_rank(api, member_id, str(sub_rank["rank_id"]), 1)
            assert resp.status_code == 200, resp.text
            body = resp.json()
            assert body["new_rank"]["rank_id"] == str(sub_rank["rank_id"])
            assert body["new_sub_index"] == 1
            # A leaf above the base always carries a derived sub label
            # (stripes: "1 Stripe"; div: "Div 2").
            assert body["new_sub_label"]
            assert body["new_display_name"]
        finally:
            _restore_leaf(api, member_id, original_rank, original_sub)
            janitor.clean()

    def test_set_member_rank_sub_ranked_without_index_is_400(
        self, api: httpx.Client, ladder: list[dict], flow_member: dict
    ) -> None:
        """A sub-ranked main requires a sub_index — omitting it is a 400
        (the leaf invariant is enforced server-side, no member write)."""
        sub_rank = next(
            (r for r in ladder if r["sub_rank_count"] and r["sub_rank_count"] > 0),
            None,
        )
        if sub_rank is None:
            pytest.skip("No sub-ranked main in the seed")

        resp = _set_member_rank(
            api, flow_member["member_id"], str(sub_rank["rank_id"]), None
        )
        assert resp.status_code == 400, resp.text

    def test_promote_at_top_of_ladder_is_409(
        self, api: httpx.Client, ladder: list[dict], flow_member: dict
    ) -> None:
        member_id = flow_member["member_id"]
        original_rank = flow_member["original_rank_id"]
        original_sub = flow_member["original_sub_index"]
        top_rank, top_sub = _top_leaf(ladder)

        janitor = _ActivityJanitor(member_id)
        try:
            assert (
                _set_member_rank(
                    api, member_id, str(top_rank), top_sub
                ).status_code
                == 200
            )
            resp = api.post(
                f"{RANKS_BASE}/promote-member",
                json={"gym_id": GYM_ID, "member_id": str(member_id)},
            )
            assert resp.status_code == 409, resp.text
        finally:
            _restore_leaf(api, member_id, original_rank, original_sub)
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
        """Submitting the CURRENT full ordering must succeed and leave the
        ladder unchanged — the shift/finalize dance runs against the real
        non-deferrable unique constraint."""
        payload = [
            {
                "rank_id": str(r["rank_id"]),
                "main_rank_num_order": r["main_rank_num_order"],
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
                    },
                ],
            },
        )
        assert resp.status_code == 400, resp.text
        assert "entire ladder" in resp.json()["detail"]


# ---------------------------------------------------------------------------
# paginated member reads (ready-to-promote board + members-in-rank roster)
# ---------------------------------------------------------------------------


class TestPaginatedReads:
    def test_ready_to_promote_shape(
        self, api: httpx.Client, ladder: list[dict]
    ) -> None:
        """GET /ready-to-promote returns a paginated proximity board."""
        resp = api.get(
            f"{RANKS_BASE}/ready-to-promote",
            params={"gym_id": GYM_ID, "start_index": 0, "count": 25},
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert isinstance(body["items"], list)
        assert isinstance(body["total_count"], int)
        for row in body["items"]:
            for field in (
                "member_id",
                "main_rank_id",
                "main_name",
                "current_sub_index",
                "sub_label",
                "classes_since",
                "step_denominator",
            ):
                assert field in row, f"ready-to-promote row missing '{field}'"
            UUID(row["member_id"])
            UUID(row["main_rank_id"])
            assert isinstance(row["classes_since"], int)

    def test_members_in_rank_shape(
        self, api: httpx.Client, ladder: list[dict]
    ) -> None:
        """GET /{rank_id}/members returns the paginated rank roster."""
        rank_id = str(ladder[0]["rank_id"])
        resp = api.get(
            f"{RANKS_BASE}/{rank_id}/members",
            params={"start_index": 0, "count": 25},
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert isinstance(body["items"], list)
        assert isinstance(body["total_count"], int)
        for row in body["items"]:
            for field in (
                "member_id",
                "name",
                "current_sub_index",
                "sub_label",
                "classes_since",
                "step_denominator",
            ):
                assert field in row, f"members-in-rank row missing '{field}'"
            UUID(row["member_id"])

    def test_members_in_rank_unknown_rank_is_404(
        self, api: httpx.Client
    ) -> None:
        resp = api.get(f"{RANKS_BASE}/{uuid4()}/members")
        assert resp.status_code == 404, resp.text


# ---------------------------------------------------------------------------
# enable-toggle backfill assigns the base leaf + writes rank_changed audit
# ---------------------------------------------------------------------------


class TestEnableBackfillAudit:
    def test_backfill_assigns_base_leaf_and_logs_activity(
        self, api: httpx.Client, ladder: list[dict], flow_member: dict
    ) -> None:
        """Unassign a member, flip enabled false→true: the backfill must
        give them the LOWEST rank's BASE leaf (sub-index 0 when it has
        sub-ranks, else NULL) and write a rank_changed activity (the
        progress anchor starts at the backfill)."""
        member_id = flow_member["member_id"]
        original_rank = flow_member["original_rank_id"]
        original_sub = flow_member["original_sub_index"]
        lowest = ladder[0]

        janitor = _ActivityJanitor(member_id)
        # The false→true toggle backfills EVERY rank-less member of the gym,
        # not just flow_member. Snapshot the collateral ones now (flow_member
        # excluded — it's restored explicitly below) so their backfilled leaf
        # and audit rows are undone in teardown too, leaving the shared gym
        # exactly as this test found it.
        collateral = _CollateralBackfillJanitor(exclude=member_id)
        try:
            assert _set_member_rank(api, member_id, None).status_code == 200

            for enabled in (False, True):
                resp = api.put(
                    f"{RANKS_BASE}/enabled",
                    json={"gym_id": GYM_ID, "is_rank_enabled": enabled},
                )
                assert resp.status_code == 200, resp.text

            db_rank, db_sub = _read_leaf(member_id)
            assert str(db_rank) == str(lowest["rank_id"])
            assert db_sub == _base_leaf(lowest)

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
            # Re-assert the seed's enabled state, restore the member's leaf,
            # and drop every audit row this flow added — for flow_member and
            # for every other member the backfill touched.
            api.put(
                f"{RANKS_BASE}/enabled",
                json={"gym_id": GYM_ID, "is_rank_enabled": True},
            )
            _restore_leaf(api, member_id, original_rank, original_sub)
            janitor.clean()
            collateral.clean()
