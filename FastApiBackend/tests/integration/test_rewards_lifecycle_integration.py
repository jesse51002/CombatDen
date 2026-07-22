"""Live-DB integration tests for the rewards redemption lifecycle.

The money-adjacent edge-case matrix for the approval-queue rework: pending
redeem → approve/reject with point_cost SNAPSHOT semantics, the staff
override drain, the deactivated-reward regression (a soft-deleted reward
must reject BOTH redeem paths without touching the balance), the points-
adjust floor, and pending-queue pagination.

Every mutation goes through the LIVE FastAPI backend (the ``api`` fixture —
the seeded owner's Bearer token, from ``tests/integration/conftest.py``).
The DB is touched directly (via the root ``created`` fixture's ``db_pool``)
only to seed a known ``points_balance`` before a test and to read back
ground truth after — never to bypass the endpoint under test.

Test functions are ``async def`` so they share ONE event loop with the
``created`` fixture's ``DirectDatabasePool`` (its SQLAlchemy async engine is
loop-affined — driving it from a second, freshly-spun loop mid-test corrupts
its connections). The ``api`` fixture is a plain sync ``httpx.Client``, so
its calls are routed through ``_req`` (``asyncio.to_thread``) instead of
being awaited directly — keeps the blocking I/O off the event loop and
avoids calling a sync httpx method inline from async code.

Each test creates its own member (``created.member(...)``) and its own
reward (``created.reward(...)`` — a plain DB insert, no Stripe object,
unlike members/plans/discounts) and tracks any redemption row the live API
returns via ``created.track_redemption(...)``. ``CreatedResources.cleanup()``
(``tests/conftest.py``) deletes redemption rows before members/rewards on
teardown (FK-safe), so nothing here needs its own try/finally.

REQUIRES all three migrations applied to the shared local Supabase DB:
  - ``20260628100000_reward_redemption_status.sql`` (status/resolved_at + enum)
  - ``20260703000000_rewards_label_and_timestamps.sql`` (price_label,
    requested_at/resolved_at renames, the resolved_matches_status CHECK)
  - ``20260703010000_gym_rewards_image_and_label_required.sql`` (image_url +
    price_label NULL-backfill + NOT NULL — RewardResponse types both as
    required ``str``, so a legacy NULL row 500s on read until backfilled)
Until all land, every mutating call in this file 500s (undefined column) or
422s (unknown schema field) — that is a missing migration, not a code defect.
"""

from __future__ import annotations

import asyncio
from typing import Any
from uuid import UUID

import httpx
import pytest
from sqlalchemy import text

from src.shared.database import DirectDatabasePool
from tests.conftest import CreatedResources
from tests.helpers.db_reads import get_points_balance
from tests.helpers.db_writes import set_points_balance

REWARDS_BASE = "/api/v1/rewards"
MEMBERS_BASE = "/api/v1/members"


async def _req(fn, *args: Any, **kwargs: Any) -> httpx.Response:
    """Run a blocking ``httpx.Client`` call off the event loop thread.

    ``api`` is a plain sync client (shared across the whole integration
    suite); calling it inline from an ``async def`` test would block the
    loop the ``created`` fixture's DB pool also needs, so every call goes
    through ``asyncio.to_thread``.
    """
    return await asyncio.to_thread(fn, *args, **kwargs)


async def _redemption_count_for_member(
    db_pool: DirectDatabasePool, member_id: UUID
) -> int:
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT COUNT(*) FROM member_reward_redemptions "
                "WHERE member_id = :id"
            ),
            {"id": str(member_id)},
        )
        return result.scalar_one()


async def _setup_member_and_reward(
    gym_id: str,
    created: CreatedResources,
    *,
    balance: int,
    point_cost: int,
    title: str = "ZZ Test Reward",
):
    """Create a member + a reward for this gym and seed a known balance."""
    gym_uuid = UUID(gym_id)
    member = await created.member(gym_uuid)
    reward = await created.reward(gym_uuid, point_cost=point_cost, title=title)
    await set_points_balance(created.db_pool, member.member_id, balance)
    return member, reward


# ---------------------------------------------------------------------------
# 1-3: redeem -> approve / reject, snapshot semantics
# ---------------------------------------------------------------------------


class TestApprovalLifecycle:
    async def test_redeem_pending_then_approve_is_guarded(
        self, api: httpx.Client, created: CreatedResources, gym_id: str
    ) -> None:
        """Redeem debits exactly once and lands 'pending'; approve flips the
        status without touching the balance; a second approve 409s."""
        member, reward = await _setup_member_and_reward(
            gym_id, created, balance=250, point_cost=100
        )

        resp = await _req(
            api.post,
            f"{REWARDS_BASE}/{reward.reward_id}/redeem",
            json={"member_id": str(member.member_id)},
        )
        assert resp.status_code == 201, resp.text
        body = resp.json()
        created.track_redemption(UUID(body["redemption_id"]))
        assert body["status"] == "pending"
        assert body["resolved_at"] is None
        assert body["points_balance_after"] == 150

        # Debited exactly once.
        assert (await get_points_balance(created.db_pool, member.member_id)) == 150

        approve = await _req(
            api.post, f"{REWARDS_BASE}/redemptions/{body['redemption_id']}/approve"
        )
        assert approve.status_code == 200, approve.text
        approved = approve.json()
        assert approved["status"] == "approved"
        assert approved["resolved_at"] is not None

        # Approve never touches the balance.
        assert (await get_points_balance(created.db_pool, member.member_id)) == 150

        second_approve = await _req(
            api.post, f"{REWARDS_BASE}/redemptions/{body['redemption_id']}/approve"
        )
        assert second_approve.status_code == 409, second_approve.text

    async def test_redeem_then_reject_refunds_exactly_once(
        self, api: httpx.Client, created: CreatedResources, gym_id: str
    ) -> None:
        """Reject refunds the snapshot point_cost exactly once; a second
        reject 409s with no second refund; approve-after-reject 409s too."""
        member, reward = await _setup_member_and_reward(
            gym_id, created, balance=200, point_cost=80
        )

        resp = await _req(
            api.post,
            f"{REWARDS_BASE}/{reward.reward_id}/redeem",
            json={"member_id": str(member.member_id)},
        )
        assert resp.status_code == 201, resp.text
        redemption_id = resp.json()["redemption_id"]
        created.track_redemption(UUID(redemption_id))
        assert (await get_points_balance(created.db_pool, member.member_id)) == 120

        reject = await _req(
            api.post, f"{REWARDS_BASE}/redemptions/{redemption_id}/reject"
        )
        assert reject.status_code == 200, reject.text
        rejected = reject.json()
        assert rejected["status"] == "rejected"
        assert rejected["resolved_at"] is not None
        assert rejected["points_balance_after"] == 200
        assert (await get_points_balance(created.db_pool, member.member_id)) == 200

        second_reject = await _req(
            api.post, f"{REWARDS_BASE}/redemptions/{redemption_id}/reject"
        )
        assert second_reject.status_code == 409, second_reject.text
        # No second refund.
        assert (await get_points_balance(created.db_pool, member.member_id)) == 200

        approve_after_reject = await _req(
            api.post, f"{REWARDS_BASE}/redemptions/{redemption_id}/approve"
        )
        assert approve_after_reject.status_code == 409, approve_after_reject.text

    async def test_reject_refunds_original_point_cost_snapshot(
        self, api: httpx.Client, created: CreatedResources, gym_id: str
    ) -> None:
        """The redemption row snapshots point_cost at redeem time; a reject
        refunds THAT snapshot even after the reward's point_cost changes."""
        member, reward = await _setup_member_and_reward(
            gym_id, created, balance=300, point_cost=100
        )

        resp = await _req(
            api.post,
            f"{REWARDS_BASE}/{reward.reward_id}/redeem",
            json={"member_id": str(member.member_id)},
        )
        assert resp.status_code == 201, resp.text
        redemption_id = resp.json()["redemption_id"]
        created.track_redemption(UUID(redemption_id))
        assert resp.json()["point_cost"] == 100
        assert (await get_points_balance(created.db_pool, member.member_id)) == 200

        # Change the reward's point_cost via the API AFTER the snapshot.
        put_resp = await _req(
            api.put,
            f"{REWARDS_BASE}/{reward.reward_id}",
            json={"data": {"point_cost": 500}},
        )
        assert put_resp.status_code == 200, put_resp.text
        assert put_resp.json()["point_cost"] == 500

        reject = await _req(
            api.post, f"{REWARDS_BASE}/redemptions/{redemption_id}/reject"
        )
        assert reject.status_code == 200, reject.text
        # Refund uses the ORIGINAL snapshot (100), not the new cost (500).
        assert reject.json()["points_balance_after"] == 300
        assert (await get_points_balance(created.db_pool, member.member_id)) == 300


# ---------------------------------------------------------------------------
# 4-6: staff override + the deactivated-reward regression + insufficient points
# ---------------------------------------------------------------------------


class TestStaffOverrideAndRegressions:
    async def test_override_drains_balance_to_exactly_zero(
        self, api: httpx.Client, created: CreatedResources, gym_id: str
    ) -> None:
        """Staff override on a member whose balance < point_cost drains the
        balance to EXACTLY zero and snapshots the NOMINAL point_cost."""
        member, reward = await _setup_member_and_reward(
            gym_id, created, balance=120, point_cost=500
        )

        resp = await _req(
            api.post,
            f"{REWARDS_BASE}/{reward.reward_id}/redeem-for-member",
            json={"member_id": str(member.member_id), "override": True},
        )
        assert resp.status_code == 201, resp.text
        body = resp.json()
        created.track_redemption(UUID(body["redemption_id"]))
        assert body["status"] == "approved"
        assert body["point_cost"] == 500  # nominal snapshot, not the debit
        assert body["points_balance_after"] == 0
        assert (await get_points_balance(created.db_pool, member.member_id)) == 0

    async def test_redeem_for_member_approves_existing_pending_no_double_debit(
        self, api: httpx.Client, created: CreatedResources, gym_id: str
    ) -> None:
        """The SMART staff path: with an open pending redemption for the same
        reward, redeem-for-member APPROVES that row (override included — the
        points were debited at request time, so nothing drains) instead of
        double-charging; with the pending gone, the same call falls through
        to a fresh debit."""
        member, reward = await _setup_member_and_reward(
            gym_id, created, balance=1000, point_cost=300
        )

        # Member requests → pending, debited once (1000 → 700).
        request_resp = await _req(
            api.post,
            f"{REWARDS_BASE}/{reward.reward_id}/redeem",
            json={"member_id": str(member.member_id)},
        )
        assert request_resp.status_code == 201, request_resp.text
        pending = request_resp.json()
        created.track_redemption(UUID(pending["redemption_id"]))
        assert pending["status"] == "pending"
        assert pending["points_balance_after"] == 700

        # Staff redeem-for-member (override=True, the aggressive path) must
        # approve THAT row — same redemption_id, no drain, balance untouched.
        smart = await _req(
            api.post,
            f"{REWARDS_BASE}/{reward.reward_id}/redeem-for-member",
            json={"member_id": str(member.member_id), "override": True},
        )
        assert smart.status_code == 201, smart.text
        fulfilled = smart.json()
        assert fulfilled["redemption_id"] == pending["redemption_id"]
        assert fulfilled["status"] == "approved"
        assert fulfilled["resolved_at"] is not None
        assert fulfilled["points_balance_after"] == 700
        assert (await get_points_balance(created.db_pool, member.member_id)) == 700

        # The fulfilled request left the queue: approving it again 409s.
        re_approve = await _req(
            api.post,
            f"{REWARDS_BASE}/redemptions/{pending['redemption_id']}/approve",
        )
        assert re_approve.status_code == 409, re_approve.text

        # No pending left → the same staff call now mints a FRESH debit
        # (700 → 400) with a new redemption id.
        fresh = await _req(
            api.post,
            f"{REWARDS_BASE}/{reward.reward_id}/redeem-for-member",
            json={"member_id": str(member.member_id), "override": False},
        )
        assert fresh.status_code == 201, fresh.text
        fresh_body = fresh.json()
        created.track_redemption(UUID(fresh_body["redemption_id"]))
        assert fresh_body["redemption_id"] != pending["redemption_id"]
        assert fresh_body["points_balance_after"] == 400
        assert (await get_points_balance(created.db_pool, member.member_id)) == 400

    async def test_deactivated_reward_blocks_both_redeem_paths(
        self, api: httpx.Client, created: CreatedResources, gym_id: str
    ) -> None:
        """REGRESSION: a soft-deleted (is_active=false) reward must reject
        BOTH the member redeem AND the staff override path with 400 — and
        the member's balance must be completely untouched by either."""
        member, reward = await _setup_member_and_reward(
            gym_id, created, balance=500, point_cost=50
        )

        deactivate = await _req(api.delete, f"{REWARDS_BASE}/{reward.reward_id}")
        assert deactivate.status_code == 200, deactivate.text
        assert deactivate.json()["is_active"] is False

        balance_before = await get_points_balance(created.db_pool, member.member_id)
        assert balance_before == 500

        redeem = await _req(
            api.post,
            f"{REWARDS_BASE}/{reward.reward_id}/redeem",
            json={"member_id": str(member.member_id)},
        )
        assert redeem.status_code == 400, redeem.text
        assert (
            await get_points_balance(created.db_pool, member.member_id)
        ) == balance_before

        override = await _req(
            api.post,
            f"{REWARDS_BASE}/{reward.reward_id}/redeem-for-member",
            json={"member_id": str(member.member_id), "override": True},
        )
        assert override.status_code == 400, override.text
        assert (
            await get_points_balance(created.db_pool, member.member_id)
        ) == balance_before

    async def test_insufficient_points_without_override_returns_400(
        self, api: httpx.Client, created: CreatedResources, gym_id: str
    ) -> None:
        """A plain (non-override) redeem with too few points 400s, leaves
        the balance untouched, and writes no redemption row."""
        member, reward = await _setup_member_and_reward(
            gym_id, created, balance=10, point_cost=1000
        )

        resp = await _req(
            api.post,
            f"{REWARDS_BASE}/{reward.reward_id}/redeem",
            json={"member_id": str(member.member_id)},
        )
        assert resp.status_code == 400, resp.text
        assert (await get_points_balance(created.db_pool, member.member_id)) == 10
        assert (
            await _redemption_count_for_member(created.db_pool, member.member_id)
        ) == 0


# ---------------------------------------------------------------------------
# 7: manual points adjustment — award / floor-guarded deduct
# ---------------------------------------------------------------------------


class TestPointsAdjustment:
    async def test_award_deduct_and_floor_at_zero(
        self, api: httpx.Client, created: CreatedResources, gym_id: str
    ) -> None:
        member = await created.member(UUID(gym_id))
        await set_points_balance(created.db_pool, member.member_id, 100)

        award = await _req(
            api.post, f"{MEMBERS_BASE}/{member.member_id}/points", json={"amount": 50}
        )
        assert award.status_code == 200, award.text
        assert award.json()["points_balance"] == 150

        underflow = await _req(
            api.post,
            f"{MEMBERS_BASE}/{member.member_id}/points",
            json={"amount": -1000},
        )
        assert underflow.status_code == 400, underflow.text
        assert (await get_points_balance(created.db_pool, member.member_id)) == 150

        exact_zero = await _req(
            api.post,
            f"{MEMBERS_BASE}/{member.member_id}/points",
            json={"amount": -150},
        )
        assert exact_zero.status_code == 200, exact_zero.text
        assert exact_zero.json()["points_balance"] == 0


# ---------------------------------------------------------------------------
# 8-9: gym-wide pending queue — soft-deleted reward visibility + pagination
# ---------------------------------------------------------------------------


class TestPendingQueue:
    async def test_pending_queue_and_approve_survive_soft_deleted_reward(
        self, api: httpx.Client, created: CreatedResources, gym_id: str
    ) -> None:
        """A pending redemption whose reward gets soft-deleted mid-flight
        still shows up in the pending queue, and approve still works."""
        member, reward = await _setup_member_and_reward(
            gym_id,
            created,
            balance=200,
            point_cost=60,
            title="ZZ Soft-Deleted Reward Test",
        )

        resp = await _req(
            api.post,
            f"{REWARDS_BASE}/{reward.reward_id}/redeem",
            json={"member_id": str(member.member_id)},
        )
        assert resp.status_code == 201, resp.text
        redemption_id = resp.json()["redemption_id"]
        created.track_redemption(UUID(redemption_id))

        deactivate = await _req(api.delete, f"{REWARDS_BASE}/{reward.reward_id}")
        assert deactivate.status_code == 200, deactivate.text

        pending = await _req(
            api.get,
            f"{REWARDS_BASE}/redemptions/pending",
            params={"gym_id": gym_id, "limit": 200},
        )
        assert pending.status_code == 200, pending.text
        ids = {item["redemption_id"] for item in pending.json()["items"]}
        assert redemption_id in ids, (
            "pending queue must still surface a row whose reward was "
            "soft-deleted"
        )

        approve = await _req(
            api.post, f"{REWARDS_BASE}/redemptions/{redemption_id}/approve"
        )
        assert approve.status_code == 200, approve.text
        assert approve.json()["status"] == "approved"

    async def test_pending_queue_pagination(
        self, api: httpx.Client, created: CreatedResources, gym_id: str
    ) -> None:
        """limit/offset page correctly over a known set of pending rows."""
        baseline = await _req(
            api.get,
            f"{REWARDS_BASE}/redemptions/pending",
            params={"gym_id": gym_id, "limit": 1},
        )
        assert baseline.status_code == 200, baseline.text
        if baseline.json()["total"] != 0:
            pytest.skip(
                "Gym already has pending redemptions outstanding (another "
                "run's leftovers) — skipping the exact-count pagination "
                "assertion to avoid a false failure on a shared DB"
            )

        reward = await created.reward(UUID(gym_id), point_cost=10)
        redemption_ids: list[str] = []
        for _ in range(3):
            member = await created.member(UUID(gym_id))
            await set_points_balance(created.db_pool, member.member_id, 100)
            resp = await _req(
                api.post,
                f"{REWARDS_BASE}/{reward.reward_id}/redeem",
                json={"member_id": str(member.member_id)},
            )
            assert resp.status_code == 201, resp.text
            redemption_id = resp.json()["redemption_id"]
            created.track_redemption(UUID(redemption_id))
            redemption_ids.append(redemption_id)

        page1 = await _req(
            api.get,
            f"{REWARDS_BASE}/redemptions/pending",
            params={"gym_id": gym_id, "limit": 2},
        )
        assert page1.status_code == 200, page1.text
        page1_body = page1.json()
        assert len(page1_body["items"]) == 2
        assert page1_body["total"] == 3

        page2 = await _req(
            api.get,
            f"{REWARDS_BASE}/redemptions/pending",
            params={"gym_id": gym_id, "limit": 2, "offset": 2},
        )
        assert page2.status_code == 200, page2.text
        page2_body = page2.json()
        assert len(page2_body["items"]) == 1
        assert page2_body["total"] == 3

        # The two pages together cover exactly the 3 rows we created.
        seen_ids = {item["redemption_id"] for item in page1_body["items"]}
        seen_ids |= {item["redemption_id"] for item in page2_body["items"]}
        assert seen_ids == set(redemption_ids)


# ---------------------------------------------------------------------------
# Regression: a reward from ANOTHER gym must not burn the member's points
# ---------------------------------------------------------------------------


class TestCrossGymRedeemDoesNotBurnPoints:
    """A foreign ``reward_id`` must cost the member nothing.

    ``redeem_reward.sql`` debits and inserts in two data-modifying CTEs.
    Postgres runs EVERY such CTE exactly once regardless of whether the
    final query reads it, so a guard that lives only on the INSERT
    suppresses the redemption row while the debit still lands — and the
    service commits before raising, so the loss is permanent. The gym
    check used to sit only on the insert's join; this pins it to the
    debit as well.
    """

    @pytest.mark.asyncio
    async def test_foreign_reward_leaves_balance_untouched(
        self, api: httpx.Client, gym_id: str, created: CreatedResources
    ) -> None:
        member = await created.member(UUID(gym_id))
        await set_points_balance(created.db_pool, member.member_id, 500)

        # A throwaway gym, so its reward is genuinely foreign to the member.
        async with created.db_pool.session() as session:
            other_gym_id = (
                await session.execute(
                    text(
                        "INSERT INTO gyms (gym_name) VALUES (:name) "
                        "RETURNING gym_id"
                    ),
                    {"name": "ZZ CrossGym Redeem Test"},
                )
            ).scalar_one()
            await session.commit()

        try:
            foreign_reward = await created.reward(
                other_gym_id, point_cost=100, title="ZZ Foreign Reward"
            )

            resp = await _req(
                api.post,
                f"{REWARDS_BASE}/{foreign_reward.reward_id}/redeem",
                json={"member_id": str(member.member_id)},
            )

            # However it is refused, it must not be refused AFTER taking
            # the points.
            assert resp.status_code >= 400, resp.text
            assert (
                await get_points_balance(created.db_pool, member.member_id)
            ) == 500, "cross-gym redeem burned the member's points"
            assert (
                await _redemption_count_for_member(
                    created.db_pool, member.member_id
                )
            ) == 0
        finally:
            async with created.db_pool.session() as session:
                await session.execute(
                    text("DELETE FROM gym_rewards WHERE gym_id = :g"),
                    {"g": str(other_gym_id)},
                )
                await session.execute(
                    text("DELETE FROM gyms WHERE gym_id = :g"),
                    {"g": str(other_gym_id)},
                )
                await session.commit()
