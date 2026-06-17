"""Adversarial QA for the payer-centric billing feature (paid_by_member_id).

Fast, DB + validation + CRM-only-cancel level (no Stripe charges) — these are
the safety-critical invariants of the per-membership payer model:

- payer authorization (`_assert_payer_allowed`): self / linked-parent allowed;
  sibling / unlinked stranger rejected — and the start op's `_check_links`
  agrees with it.
- the `paid_by_member_id` immutability trigger rejects an in-place change.
- `PaymentSyncCancel` is payer-scoped: a gone sub cancels ONLY that payer's
  rows + nulls ONLY that payer's sub id, never another payer's live rows.
- the `member_memberships_status` freeze owner is the PAYER, not the
  topological parent (a self-payer's freeze is independent of the parent).
- the reconciler lists each distinct payer exactly once.
- the webhook item lookup returns the membership's payer.

These run against the real local Supabase; everything created is tracked via the
`created` fixture. No Stripe subscription/invoice is created here — engine
convergence with real Stripe is covered by test_start_family / test_one_time_*.
"""

from uuid import UUID, uuid4

import pytest
from sqlalchemy import text

from src.memberships import SQL_DIR
from src.memberships.memberships_schema import (
    MemberMembershipsStartItem,
    MemberMembershipsStartRequest,
)
from src.reconciler import SQL_DIR as RECONCILER_SQL_DIR
from src.shared.gym_stripe_service import GymStripeService
from src.shared.payer_resolver import PayerResolver
from src.shared.sql_loader import load_sql
from src.stripe_webhooks import SQL_DIR as WEBHOOK_SQL_DIR
from src.sync.service.sync_cancel import PaymentSyncCancel

_PRICE = 5000


@pytest.fixture
def payer_resolver_factory(db_pool) -> PayerResolver:
    """The shared payer resolver, built against the real DB."""
    return PayerResolver(db_pool, GymStripeService(db_pool))


@pytest.fixture(autouse=True)
async def _unlink_created_on_teardown(db_pool, created):
    """Clear `account_linked_to_id` on everything the test created before the
    `created` fixture deletes members.

    The fixture deletes members in creation order (parent first), but the
    `fk_member_linked_account` self-FK blocks deleting a parent a child still
    references. This runs first (it depends on `created`, so it tears down
    before it), severing the links so the member deletes succeed.
    """
    yield
    if created.members:
        async with db_pool.session() as session:
            await session.execute(
                text(
                    "UPDATE members SET account_linked_to_id = NULL "
                    "WHERE member_id = ANY(:ids)"
                ),
                {"ids": [str(m) for m in created.members]},
            )
            await session.commit()


# ── DB helpers ─────────────────────────────────────────────────


async def _insert_recurring(
    db_pool,
    *,
    member_id: UUID,
    paid_by: UUID,
    gym_id: UUID,
    plan,
    stripe_item_id: str | None,
    sync_status: str = "applied",
) -> UUID:
    """Insert a recurring membership row with an explicit payer."""
    sql = """
        INSERT INTO member_memberships_unfiltered (
            member_id, paid_by_member_id, gym_id, plan_id, price_id,
            start_date, stripe_item_id, total_price, stripe_sync_status
        ) VALUES (
            :member_id, :paid_by, :gym_id, :plan_id, :price_id,
            CURRENT_DATE - 7, :stripe_item_id, :total_price,
            CAST(:sync_status AS stripe_sync_status)
        )
        RETURNING item_id
    """
    async with db_pool.session() as session:
        result = await session.execute(
            text(sql),
            {
                "member_id": str(member_id),
                "paid_by": str(paid_by),
                "gym_id": str(gym_id),
                "plan_id": str(plan.plan_id),
                "price_id": str(plan.price_id),
                "stripe_item_id": stripe_item_id,
                "total_price": _PRICE,
                "sync_status": sync_status,
            },
        )
        row = result.mappings().fetchone()
        await session.commit()
    return UUID(str(row["item_id"]))


async def _row(db_pool, item_id: UUID) -> dict | None:
    async with db_pool.session() as session:
        res = await session.execute(
            text(
                "SELECT cancel_date, stripe_sync_status, paid_by_member_id "
                "FROM member_memberships_unfiltered WHERE item_id = :id"
            ),
            {"id": str(item_id)},
        )
        r = res.mappings().fetchone()
    return dict(r) if r else None


async def _status(db_pool, item_id: UUID) -> str | None:
    async with db_pool.session() as session:
        res = await session.execute(
            text(
                "SELECT status FROM member_memberships_status "
                "WHERE item_id = :id"
            ),
            {"id": str(item_id)},
        )
        r = res.mappings().fetchone()
    return r["status"] if r else None


async def _sub_id(db_pool, member_id: UUID) -> str | None:
    async with db_pool.session() as session:
        res = await session.execute(
            text("SELECT stripe_sub_id_month FROM members WHERE member_id = :id"),
            {"id": str(member_id)},
        )
        r = res.mappings().fetchone()
    return r["stripe_sub_id_month"] if r else None


async def _set_sub_id(db_pool, member_id: UUID, sub_id: str | None) -> None:
    async with db_pool.session() as session:
        await session.execute(
            text(
                "UPDATE members SET stripe_sub_id_month = :s WHERE member_id = :id"
            ),
            {"s": sub_id, "id": str(member_id)},
        )
        await session.commit()


async def _set_freeze(db_pool, member_id: UUID) -> None:
    """Put the member in an active freeze window (today .. +30d)."""
    async with db_pool.session() as session:
        await session.execute(
            text(
                "UPDATE members SET freeze_start_date = CURRENT_DATE - 1, "
                "freeze_end_date = CURRENT_DATE + 30 WHERE member_id = :id"
            ),
            {"id": str(member_id)},
        )
        await session.commit()


async def _link(db_pool, child: UUID, parent: UUID) -> None:
    sql = load_sql(SQL_DIR / "member_memberships_link.sql")
    async with db_pool.session() as session:
        await session.execute(
            text(sql),
            {"member_id": str(child), "parent_member_id": str(parent)},
        )
        await session.commit()


def _charge_sub(memberships_service):
    """The charge_card sub-service — carries the base `_assert_payer_allowed`."""
    return memberships_service._charge_card


# ── 1 · payer authorization matrix (_assert_payer_allowed) ─────


async def test_assert_payer_allowed_self_ok(
    memberships_service, db_pool, gym_id, created
):
    """A member is always allowed to pay for their own membership."""
    member = await created.member(gym_id)
    # No raise.
    await _charge_sub(memberships_service)._assert_payer_allowed(
        member.member_id, member.member_id
    )


async def test_assert_payer_allowed_linked_parent_ok(
    memberships_service, db_pool, gym_id, created
):
    """A member's linked parent is an allowed payer."""
    parent = await created.member(gym_id)
    child = await created.member(gym_id)
    await _link(db_pool, child.member_id, parent.member_id)
    await _charge_sub(memberships_service)._assert_payer_allowed(
        child.member_id, parent.member_id
    )


async def test_assert_payer_allowed_sibling_rejected(
    memberships_service, db_pool, gym_id, created
):
    """A sibling (linked to the same parent, not to each other) cannot pay."""
    parent = await created.member(gym_id)
    child_a = await created.member(gym_id)
    child_b = await created.member(gym_id)
    await _link(db_pool, child_a.member_id, parent.member_id)
    await _link(db_pool, child_b.member_id, parent.member_id)
    with pytest.raises(ValueError, match="not authorized"):
        await _charge_sub(memberships_service)._assert_payer_allowed(
            child_a.member_id, child_b.member_id
        )


async def test_assert_payer_allowed_unlinked_stranger_rejected(
    memberships_service, db_pool, gym_id, created
):
    """An unrelated, unlinked member cannot pay for someone else."""
    member = await created.member(gym_id)
    stranger = await created.member(gym_id)
    with pytest.raises(ValueError, match="not authorized"):
        await _charge_sub(memberships_service)._assert_payer_allowed(
            member.member_id, stranger.member_id
        )


async def test_assert_payer_allowed_parent_cannot_be_paid_by_child(
    memberships_service, db_pool, gym_id, created
):
    """Inverse: the child is NOT an allowed payer for the parent's own row.

    Linking is one-directional for billing — the parent pays for the child,
    not vice-versa (the parent is not linked to the child).
    """
    parent = await created.member(gym_id)
    child = await created.member(gym_id)
    await _link(db_pool, child.member_id, parent.member_id)
    with pytest.raises(ValueError, match="not authorized"):
        await _charge_sub(memberships_service)._assert_payer_allowed(
            parent.member_id, child.member_id
        )


# ── 2 · start `_check_links` agrees with the base rule ─────────


async def test_start_check_links_rejects_sibling_payer(
    memberships_service, db_pool, gym_id, created
):
    """Start's batch `_check_links` rejects a sibling as payer too.

    Payer = child_a, item member = child_b (both linked to parent). child_b is
    linked to the parent, not to child_a → the same authorization rule the base
    `_assert_payer_allowed` enforces must reject it here.
    """
    parent = await created.member(gym_id)
    child_a = await created.member(gym_id)
    child_b = await created.member(gym_id)
    await _link(db_pool, child_a.member_id, parent.member_id)
    await _link(db_pool, child_b.member_id, parent.member_id)

    request = MemberMembershipsStartRequest(
        payer_member_id=child_a.member_id,
        gym_id=gym_id,
        idempotency_key=uuid4(),
        memberships=[
            MemberMembershipsStartItem(
                member_id=child_b.member_id, price_id=uuid4()
            )
        ],
    )
    with pytest.raises(ValueError, match="linked to a different|link them first"):
        await memberships_service._start_validation._check_links(request)


async def test_start_check_links_allows_linked_child(
    memberships_service, db_pool, gym_id, created
):
    """Parent paying for a linked child passes `_check_links`."""
    parent = await created.member(gym_id)
    child = await created.member(gym_id)
    await _link(db_pool, child.member_id, parent.member_id)
    request = MemberMembershipsStartRequest(
        payer_member_id=parent.member_id,
        gym_id=gym_id,
        idempotency_key=uuid4(),
        memberships=[
            MemberMembershipsStartItem(
                member_id=child.member_id, price_id=uuid4()
            )
        ],
    )
    # No raise.
    await memberships_service._start_validation._check_links(request)


# ── 3 · paid_by_member_id immutability trigger ─────────────────


async def test_paid_by_member_id_is_immutable(
    db_pool, gym_id, created
):
    """A direct UPDATE of paid_by_member_id is rejected by the DB trigger."""
    member = await created.member(gym_id)
    other = await created.member(gym_id)
    plan = await created.plan(gym_id)
    item_id = await _insert_recurring(
        db_pool,
        member_id=member.member_id,
        paid_by=member.member_id,
        gym_id=gym_id,
        plan=plan,
        stripe_item_id=f"si_{uuid4().hex[:20]}",
    )
    with pytest.raises(Exception, match="paid_by_member_id cannot be changed"):
        async with db_pool.session() as session:
            await session.execute(
                text(
                    "UPDATE member_memberships_unfiltered "
                    "SET paid_by_member_id = :other WHERE item_id = :id"
                ),
                {"other": str(other.member_id), "id": str(item_id)},
            )
            await session.commit()
    # The payer is unchanged.
    row = await _row(db_pool, item_id)
    assert UUID(str(row["paid_by_member_id"])) == member.member_id


# ── 4 · PaymentSyncCancel is payer-scoped ──────────────────────


async def test_cancel_scoped_to_one_payer_only(
    db_pool, gym_id, created, payer_resolver_factory
):
    """A gone sub cancels ONLY that payer's rows + nulls ONLY that sub id.

    Two unrelated self-paying members; cancelling payer A's dead sub must leave
    payer B's live row + sub id completely untouched.
    """
    payer_a = await created.member(gym_id)
    payer_b = await created.member(gym_id)
    plan = await created.plan(gym_id)
    item_a = await _insert_recurring(
        db_pool, member_id=payer_a.member_id, paid_by=payer_a.member_id,
        gym_id=gym_id, plan=plan, stripe_item_id=f"si_{uuid4().hex[:20]}",
    )
    item_b = await _insert_recurring(
        db_pool, member_id=payer_b.member_id, paid_by=payer_b.member_id,
        gym_id=gym_id, plan=plan, stripe_item_id=f"si_{uuid4().hex[:20]}",
    )
    await _set_sub_id(db_pool, payer_a.member_id, f"sub_{uuid4().hex[:18]}")
    await _set_sub_id(db_pool, payer_b.member_id, f"sub_{uuid4().hex[:18]}")

    profile_a = await payer_resolver_factory.resolve_payer(payer_a.member_id)
    cancelled = await PaymentSyncCancel(db_pool).cancel_dead_subscription(profile_a)

    assert cancelled == 1
    row_a = await _row(db_pool, item_a)
    row_b = await _row(db_pool, item_b)
    assert row_a["cancel_date"] is not None
    assert row_a["stripe_sync_status"] == "deleted"
    assert await _sub_id(db_pool, payer_a.member_id) is None
    # Payer B is untouched.
    assert row_b["cancel_date"] is None
    assert row_b["stripe_sync_status"] == "applied"
    assert await _sub_id(db_pool, payer_b.member_id) is not None


async def test_cancel_parent_does_not_cancel_self_paid_child_row(
    db_pool, gym_id, created, payer_resolver_factory
):
    """In a family, cancelling the PARENT's gone sub leaves the child's
    self-paid row + its own sub fully intact (different payer group)."""
    parent = await created.member(gym_id)
    child = await created.member(gym_id)
    await _link(db_pool, child.member_id, parent.member_id)
    plan_p = await created.plan(gym_id)
    plan_c = await created.plan(gym_id)

    # Parent pays for their own membership AND the child's membership on plan_p.
    parent_own = await _insert_recurring(
        db_pool, member_id=parent.member_id, paid_by=parent.member_id,
        gym_id=gym_id, plan=plan_p, stripe_item_id=f"si_{uuid4().hex[:20]}",
    )
    parent_for_child = await _insert_recurring(
        db_pool, member_id=child.member_id, paid_by=parent.member_id,
        gym_id=gym_id, plan=plan_c, stripe_item_id=f"si_{uuid4().hex[:20]}",
    )
    # Child self-pays a SECOND membership on plan_p (own sub).
    child_self = await _insert_recurring(
        db_pool, member_id=child.member_id, paid_by=child.member_id,
        gym_id=gym_id, plan=plan_p, stripe_item_id=f"si_{uuid4().hex[:20]}",
    )
    await _set_sub_id(db_pool, parent.member_id, f"sub_{uuid4().hex[:18]}")
    await _set_sub_id(db_pool, child.member_id, f"sub_{uuid4().hex[:18]}")

    profile_parent = await payer_resolver_factory.resolve_payer(parent.member_id)
    cancelled = await PaymentSyncCancel(db_pool).cancel_dead_subscription(
        profile_parent
    )

    # Both parent-paid rows cancelled; the child's self-paid row untouched.
    assert cancelled == 2
    assert (await _row(db_pool, parent_own))["stripe_sync_status"] == "deleted"
    assert (await _row(db_pool, parent_for_child))[
        "stripe_sync_status"
    ] == "deleted"
    assert (await _row(db_pool, child_self))["stripe_sync_status"] == "applied"
    assert (await _row(db_pool, child_self))["cancel_date"] is None
    assert await _sub_id(db_pool, parent.member_id) is None
    assert await _sub_id(db_pool, child.member_id) is not None


# ── 5 · status-view freeze owner = the payer ───────────────────


async def test_status_freeze_follows_self_payer_not_parent(
    db_pool, gym_id, created
):
    """A self-paid membership's frozen status follows the CHILD's window;
    freezing the parent (not the payer) does NOT freeze it."""
    parent = await created.member(gym_id)
    child = await created.member(gym_id)
    await _link(db_pool, child.member_id, parent.member_id)
    plan = await created.plan(gym_id)
    child_self = await _insert_recurring(
        db_pool, member_id=child.member_id, paid_by=child.member_id,
        gym_id=gym_id, plan=plan, stripe_item_id=f"si_{uuid4().hex[:20]}",
    )

    # Freeze the PARENT only — the child self-pays, so it must NOT freeze.
    await _set_freeze(db_pool, parent.member_id)
    assert await _status(db_pool, child_self) == "active"

    # Freeze the CHILD (the actual payer) — now it's frozen.
    await _set_freeze(db_pool, child.member_id)
    assert await _status(db_pool, child_self) == "frozen"


async def test_status_freeze_follows_parent_for_parent_paid_row(
    db_pool, gym_id, created
):
    """A parent-paid membership freezes when the PARENT (the payer) freezes."""
    parent = await created.member(gym_id)
    child = await created.member(gym_id)
    await _link(db_pool, child.member_id, parent.member_id)
    plan = await created.plan(gym_id)
    parent_paid = await _insert_recurring(
        db_pool, member_id=child.member_id, paid_by=parent.member_id,
        gym_id=gym_id, plan=plan, stripe_item_id=f"si_{uuid4().hex[:20]}",
    )
    assert await _status(db_pool, parent_paid) == "active"
    await _set_freeze(db_pool, parent.member_id)
    assert await _status(db_pool, parent_paid) == "frozen"


# ── 6 · reconciler lists each distinct payer exactly once ──────


async def test_reconciler_lists_each_payer_once(
    db_pool, gym_id, created
):
    """Two active recurring rows for one payer → that payer appears once;
    a self-paying child is its own distinct payer entry."""
    payer = await created.member(gym_id)
    child = await created.member(gym_id)
    await _link(db_pool, child.member_id, payer.member_id)
    plan1 = await created.plan(gym_id)
    plan2 = await created.plan(gym_id)

    # Payer bills two memberships (own + child's) — two rows, one payer.
    await _insert_recurring(
        db_pool, member_id=payer.member_id, paid_by=payer.member_id,
        gym_id=gym_id, plan=plan1, stripe_item_id=f"si_{uuid4().hex[:20]}",
    )
    await _insert_recurring(
        db_pool, member_id=child.member_id, paid_by=payer.member_id,
        gym_id=gym_id, plan=plan2, stripe_item_id=f"si_{uuid4().hex[:20]}",
    )
    # Child self-pays a third membership (distinct payer).
    await _insert_recurring(
        db_pool, member_id=child.member_id, paid_by=child.member_id,
        gym_id=gym_id, plan=plan1, stripe_item_id=f"si_{uuid4().hex[:20]}",
    )

    sql = load_sql(RECONCILER_SQL_DIR / "reconciler_active_billing_members.sql")
    async with db_pool.session() as session:
        res = await session.execute(text(sql))
        payers = [UUID(str(r["member_id"])) for r in res.mappings().all()]

    assert payers.count(payer.member_id) == 1, "payer must appear exactly once"
    assert payers.count(child.member_id) == 1, "self-payer is its own entry"


# ── 7 · webhook item lookup returns the payer ──────────────────


async def test_webhook_item_lookup_returns_payer(
    db_pool, gym_id, created
):
    """membership_by_stripe_item returns both owner (member_id) and the
    PAYER (paid_by_member_id) — the once-settle must target the payer's sub."""
    parent = await created.member(gym_id)
    child = await created.member(gym_id)
    await _link(db_pool, child.member_id, parent.member_id)
    plan = await created.plan(gym_id)
    si = f"si_{uuid4().hex[:20]}"
    await _insert_recurring(
        db_pool, member_id=child.member_id, paid_by=parent.member_id,
        gym_id=gym_id, plan=plan, stripe_item_id=si,
    )
    sql = load_sql(WEBHOOK_SQL_DIR / "membership_by_stripe_item.sql")
    async with db_pool.session() as session:
        res = await session.execute(
            text(sql), {"stripe_item_id": si, "gym_id": str(gym_id)}
        )
        row = res.mappings().fetchone()
    assert row is not None
    assert UUID(str(row["member_id"])) == child.member_id
    assert UUID(str(row["paid_by_member_id"])) == parent.member_id
